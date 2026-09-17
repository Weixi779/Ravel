// Created by weixi on 2026/09/17.

use crate::{BackendError, read_error};
use futures::{FutureExt, channel::oneshot, future::BoxFuture, future::Shared};
use std::{panic::AssertUnwindSafe, thread};

/// Completion means the operation and its captured native resources were dropped.
/// Clones let every close caller await the same cleanup without joining a thread.
pub(crate) type Completion = Shared<BoxFuture<'static, ()>>;

pub(crate) struct Worker<T> {
    result: oneshot::Receiver<Result<T, BackendError>>,
    pub(crate) finished: Completion,
}

impl<T> Worker<T> {
    pub(crate) async fn result(self) -> Result<T, BackendError> {
        self.finished.await;
        self.result
            .await
            .map_err(|_| read_error("The native worker stopped without a result"))?
    }
}

pub(crate) fn spawn<T: Send + 'static>(
    name: &str,
    operation: impl FnOnce() -> Result<T, BackendError> + Send + 'static,
) -> Result<Worker<T>, BackendError> {
    let (reply, result) = oneshot::channel();
    let (finished, completion) = oneshot::channel();
    thread::Builder::new()
        .name(name.into())
        .stack_size(8 * 1024 * 1024)
        .spawn(move || {
            // The closure (including its captures) is consumed before signaling completion.
            let outcome = std::panic::catch_unwind(AssertUnwindSafe(move || {
                configure_qos()?;
                operation()
            }))
            .unwrap_or_else(|_| Err(read_error("The native worker failed")));
            let _ = reply.send(outcome);
            let _ = finished.send(());
        })
        .map_err(read_error)?;
    Ok(Worker {
        result,
        finished: completion.map(|_| ()).boxed().shared(),
    })
}

#[cfg(target_vendor = "apple")]
fn configure_qos() -> Result<(), BackendError> {
    // These workers serve history and previews that the user is actively waiting for.
    // Swift task priority does not propagate across a native thread/channel boundary.
    unsafe extern "C" {
        fn pthread_set_qos_class_self_np(
            class: std::ffi::c_uint,
            priority: std::ffi::c_int,
        ) -> std::ffi::c_int;
    }
    const USER_INITIATED: std::ffi::c_uint = 0x19;
    // SAFETY: this only classifies the calling native worker, with a valid class/priority.
    let error = unsafe { pthread_set_qos_class_self_np(USER_INITIATED, 0) };
    if error == 0 {
        Ok(())
    } else {
        Err(read_error(std::io::Error::from_raw_os_error(error)))
    }
}

#[cfg(not(target_vendor = "apple"))]
fn configure_qos() -> Result<(), BackendError> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::future::Future;
    use std::sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
        mpsc,
    };
    use std::task::{Context, Poll};

    #[test]
    fn awaiting_worker_yields_and_completion_follows_resource_release() {
        struct Resource(Arc<AtomicBool>);
        impl Drop for Resource {
            fn drop(&mut self) {
                self.0.store(true, Ordering::Release);
            }
        }
        let dropped = Arc::new(AtomicBool::new(false));
        let resource = Resource(dropped.clone());
        let (release, released) = mpsc::channel();
        let worker = spawn("ravel-test", move || {
            let _resource = resource;
            released.recv().unwrap();
            Ok(42)
        })
        .unwrap();
        let completion = worker.finished.clone();
        let mut result = Box::pin(worker.result());
        assert!(matches!(
            result
                .as_mut()
                .poll(&mut Context::from_waker(futures::task::noop_waker_ref())),
            Poll::Pending
        ));
        assert!(!dropped.load(Ordering::Acquire));
        release.send(()).unwrap();
        assert_eq!(pollster::block_on(result).unwrap(), 42);
        pollster::block_on(completion);
        assert!(dropped.load(Ordering::Acquire));
    }

    #[test]
    fn panic_completes_with_error_instead_of_stranding_waiters() {
        let worker = spawn::<()>("ravel-test", || panic!("worker failure")).unwrap();
        let completion = worker.finished.clone();
        assert!(matches!(
            pollster::block_on(worker.result()),
            Err(BackendError::Read { .. })
        ));
        pollster::block_on(completion);
    }

    #[cfg(target_vendor = "apple")]
    #[test]
    fn native_worker_runs_at_user_initiated_qos() {
        let worker = spawn("ravel-test", || {
            unsafe extern "C" {
                fn qos_class_self() -> std::ffi::c_uint;
            }
            // SAFETY: queries the current thread and takes no arguments.
            Ok(unsafe { qos_class_self() })
        })
        .unwrap();
        assert_eq!(pollster::block_on(worker.result()).unwrap(), 0x19);
    }
}
