from __future__ import annotations

import sys

def _run_prisma_cli() -> None:
    from prisma.cli import main as prisma_main

    prisma_main(args=["prisma", *sys.argv[2:]])


def _run_litellm_proxy() -> None:
    from litellm.proxy.proxy_cli import run_server

    # Reuse LiteLLM's Click entrypoint so the bundled executable keeps the
    # existing CLI surface (`--config`, `--port`, `--health`, etc).
    run_server(args=sys.argv[1:], standalone_mode=False)


def main() -> None:
    if len(sys.argv) > 1 and sys.argv[1] == "--__run-prisma__":
        _run_prisma_cli()
        return

    _run_litellm_proxy()


if __name__ == "__main__":
    main()
