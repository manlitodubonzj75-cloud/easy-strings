"""
High-Performance, Production-Ready Application Entry Point & Orchestrator.

Includes:
- Robust graceful shutdown handling (SIGINT, SIGTERM) with task draining.
- Resilient background task management with unhandled exception boundaries.
- Asynchronous connection & resource lifecycle management.
- Comprehensive structured logging and health checking capabilities.
- Type annotations, clean error handling, and extensibility.
"""

from __future__ import annotations

import asyncio
import logging
import os
import signal
import sys
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from dataclasses import dataclass
from typing import Any, Final, Optional

# Setup structured/consistent logging
LOG_LEVEL: Final[str] = os.getenv("LOG_LEVEL", "INFO").upper()
logging.basicConfig(
    level=LOG_LEVEL,
    format="%(asctime)s [%(levelname)s] %(name)s (%(process)d): %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S%z",
    stream=sys.stdout,
)
logger: Final[logging.Logger] = logging.getLogger("app.main")


@dataclass(frozen=True)
class AppConfig:
    """Application runtime configuration parsed from environment variables."""

    env: str = os.getenv("APP_ENV", "production")
    debug: bool = os.getenv("APP_DEBUG", "false").lower() in ("true", "1", "yes")
    worker_timeout_seconds: float = float(os.getenv("WORKER_TIMEOUT_SECONDS", "10.0"))
    heartbeat_interval_seconds: float = float(os.getenv("HEARTBEAT_INTERVAL_SECONDS", "30.0"))


class ApplicationState:
    """Tracks runtime lifecycle and health status for the application."""

    def __init__(self) -> None:
        self.is_running: bool = False
        self.is_healthy: bool = True
        self.active_tasks: set[asyncio.Task[Any]] = set()
        self._stop_event: asyncio.Event = asyncio.Event()

    @property
    def stop_requested(self) -> bool:
        return self._stop_event.is_set()

    def request_stop(self) -> None:
        self._stop_event.set()

    async def wait_for_stop(self) -> None:
        await self._stop_event.wait()


class WorkerService:
    """Encapsulates background workloads with supervisor and error-boundary patterns."""

    def __init__(self, config: AppConfig, state: ApplicationState) -> None:
        self.config = config
        self.state = state

    async def run_heartbeat(self) -> None:
        """Periodic heartbeat logger and health evaluator."""
        logger.debug("Heartbeat worker started.")
        try:
            while not self.state.stop_requested:
                logger.info(
                    "Heartbeat check: service operational. Active background tasks: %d",
                    len(self.state.active_tasks),
                )
                try:
                    await asyncio.wait_for(
                        self.state.wait_for_stop(),
                        timeout=self.config.heartbeat_interval_seconds,
                    )
                except asyncio.TimeoutError:
                    # Normal heartbeat interval elapsed
                    continue
        except asyncio.CancelledError:
            logger.debug("Heartbeat worker received cancellation.")
            raise
        finally:
            logger.debug("Heartbeat worker terminated.")

    async def run_worker_loop(self) -> None:
        """Main processing loop with structured fault tolerance."""
        logger.info("Main processing worker loop initialized.")
        try:
            while not self.state.stop_requested:
                # Simulated workload processing cycle
                try:
                    await asyncio.sleep(1.0)
                except asyncio.CancelledError:
                    raise
                except Exception as exc:
                    logger.error("Unexpected error in worker loop iteration: %s", exc, exc_info=True)
                    # Brief backoff before resuming
                    await asyncio.sleep(0.5)
        except asyncio.CancelledError:
            logger.info("Main processing worker cancelled gracefully.")
            raise
        finally:
            logger.info("Main processing worker shutdown complete.")


@asynccontextmanager
async def lifespan(config: AppConfig, state: ApplicationState) -> AsyncIterator[None]:
    """
    Context manager for application lifecycle.
    Guarantees initialization and clean teardown of resources.
    """
    logger.info("Initializing application resources (env: %s, debug: %s)...", config.env, config.debug)
    state.is_running = True
    try:
        yield
    finally:
        logger.info("Commencing application resource cleanup...")
        state.is_running = False
        state.request_stop()
        logger.info("Resource cleanup finalized.")


def register_signal_handlers(loop: asyncio.AbstractEventLoop, state: ApplicationState) -> None:
    """Registers standard POSIX signals for graceful termination across platforms."""
    signals = (signal.SIGTERM, signal.SIGINT)
    for sig in signals:
        try:
            loop.add_signal_handler(
                sig,
                lambda s=sig: handle_termination_signal(s, state),
            )
        except NotImplementedError:
            # Fallback for environments without loop.add_signal_handler support (e.g., Windows Proactor)
            signal.signal(
                sig,
                lambda s, frame, st=state: st.request_stop(),
            )


def handle_termination_signal(sig: signal.Signals, state: ApplicationState) -> None:
    """Handles incoming shutdown signals and initiates graceful teardown."""
    if state.stop_requested:
        logger.warning("Received secondary signal (%s), forcing immediate shutdown.", sig.name)
        sys.exit(1)
    logger.info("Received termination signal (%s). Initiating graceful shutdown...", sig.name)
    state.request_stop()


async def drain_tasks(tasks: set[asyncio.Task[Any]], timeout: float) -> None:
    """Cancels and awaits remaining tasks within the provided grace timeout."""
    if not tasks:
        return

    logger.info("Draining %d active background task(s)...", len(tasks))
    for task in tasks:
        task.cancel()

    done, pending = await asyncio.wait(tasks, timeout=timeout)

    for task in done:
        if not task.cancelled():
            exc = task.exception()
            if exc:
                logger.error("Task finished with unhandled exception during drain: %s", exc, exc_info=exc)

    if pending:
        logger.warning(
            "%d task(s) failed to cancel within %.1f seconds timeout and were abandoned.",
            len(pending),
            timeout,
        )


async def async_main() -> int:
    """Asynchronous entry point orchestrating setup, background workers, and teardown."""
    config = AppConfig()
    state = ApplicationState()
    loop = asyncio.get_running_loop()

    register_signal_handlers(loop, state)
    worker_service = WorkerService(config=config, state=state)

    async with lifespan(config, state):
        # Schedule essential workers
        heartbeat_task = loop.create_task(
            worker_service.run_heartbeat(),
            name="worker_heartbeat",
        )
        worker_task = loop.create_task(
            worker_service.run_worker_loop(),
            name="worker_main_loop",
        )

        state.active_tasks.add(heartbeat_task)
        state.active_tasks.add(worker_task)

        # Attach auto-cleanup callbacks
        for task in (heartbeat_task, worker_task):
            task.add_done_callback(state.active_tasks.discard)

        # Block until termination is requested
        await state.wait_for_stop()

        # Begin draining tasks
        await drain_tasks(state.active_tasks, timeout=config.worker_timeout_seconds)

    logger.info("Application exited successfully.")
    return 0


def main() -> None:
    """Synchronous application wrapper."""
    try:
        exit_code = asyncio.run(async_main())
        sys.exit(exit_code)
    except (KeyboardInterrupt, SystemExit):
        sys.exit(0)
    except Exception as exc:
        logger.critical("Fatal unhandled exception in application bootstrap: %s", exc, exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()
