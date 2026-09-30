"""Main application entry point with robust configuration, logging, and lifecycle management."""

import asyncio
import logging
import os
import signal
import sys
from typing import Optional


class Settings:
    """Application settings loaded from environment variables."""

    def __init__(self) -> None:
        self.app_name: str = os.getenv("APP_NAME", "unified-service")
        self.env: str = os.getenv("ENV", "development").lower()
        self.log_level: str = os.getenv("LOG_LEVEL", "INFO").upper()
        self.host: str = os.getenv("HOST", "0.0.0.0")
        self.port: int = int(os.getenv("PORT", "8000"))
        self.shutdown_timeout: float = float(os.getenv("SHUTDOWN_TIMEOUT", "10.0"))


def setup_logging(level: str = "INFO") -> None:
    """Configure structured logging for the application."""
    numeric_level = getattr(logging, level, logging.INFO)
    logging.basicConfig(
        level=numeric_level,
        format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        stream=sys.stdout,
    )


class Application:
    """Core application manager supporting graceful startup and shutdown."""

    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.logger = logging.getLogger(self.__class__.__name__)
        self._stop_event = asyncio.Event()

    async def start(self) -> None:
        """Initialize resources and background workers."""
        self.logger.info("Initializing application: %s in %s mode", self.settings.app_name, self.settings.env)
        # Background loops / connection pools initialization can be added here
        self.logger.info("Application started successfully.")

    async def run(self) -> None:
        """Run the main event loop until cancellation or termination signal."""
        await self.start()
        try:
            while not self._stop_event.is_set():
                await asyncio.sleep(0.5)
        except asyncio.CancelledError:
            self.logger.info("Cancellation received in main run loop.")
        finally:
            await self.stop()

    async def stop(self) -> None:
        """Gracefully release all resources."""
        self.logger.info("Shutting down application...")
        self._stop_event.set()
        # Cleanup any background tasks or open handles here
        self.logger.info("Application shutdown complete.")

    def request_stop(self) -> None:
        """Signal the application to stop."""
        self._stop_event.set()


def install_signal_handlers(app: Application, loop: asyncio.AbstractEventLoop) -> None:
    """Register OS signal handlers for graceful termination."""
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, app.request_stop)
        except (NotImplementedError, AttributeError):
            # add_signal_handler is not implemented on Windows event loops
            signal.signal(sig, lambda *_: app.request_stop())


async def main() -> None:
    """Main asynchronous bootstrap function."""
    settings = Settings()
    setup_logging(settings.log_level)
    logger = logging.getLogger("bootstrap")

    app = Application(settings)
    loop = asyncio.get_running_loop()
    install_signal_handlers(app, loop)

    try:
        await app.run()
    except Exception as exc:
        logger.exception("Unhandled exception during execution: %s", exc)
        sys.exit(1)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except (KeyboardInterrupt, SystemExit):
        pass
