# Snowywood Project Context

Snowywood is a Space Station 13 (SS13) game server codebase, specifically a map experiment and fork based on **Ratwood** (which itself is derived from **tgstation**). It is built primarily using the **BYOND Dream Maker (DM)** language, with modern web-based UI components built in **TypeScript/React**.

## Project Architecture & Technologies

-   **BYOND (DM):** The core game engine and logic. The main project file is `roguetown.dme`.
-   **tgui:** A modern user interface framework based on **React** and **TypeScript**, located in the `/tgui` directory. It uses **Bun** as its package manager and runtime.
-   **Rust (rust_g):** External library for performance-critical tasks like hashing, regex, and database interactions.
-   **Juke Build:** A build orchestration system running on Bun, located in `tools/build/`.
-   **SpacemanDMM:** A suite of tools for DM, including a linter (`dreamchecker`) and language server.

## Key Directory Structure

-   `/_maps/`: Map files (`.dmm`) and metadata (`.json`).
-   `/bin/`: Command-line scripts for building, testing, and running the server.
-   `/code/`: The core DM source code, organized by module (e.g., `controllers/`, `datums/`, `game/`, `modules/`).
    -   `code/__DEFINES/`: Header files with preprocessor macros.
    -   `code/_compile_options.dm`: Global compilation flags (e.g., `TESTING`, `DEBUG`).
-   `/config/`: Server configuration files.
-   `/data/`: Persistent data, logs, and player saves.
-   `/html/`: Legacy HTML assets.
-   `/icons/`: Sprite files in BYOND's `.dmi` format.
-   `/interface/`: Skin and interface definitions (`.dmf`).
-   `/modular_*/`: Modular content extensions (e.g., `modular_azurepeak`, `modular_deserttown`).
-   `/tgui/`: Source for the React-based UI.
-   `/tools/`: Build and development tools.

## Development Workflow

### Building the Project

The project uses a unified build system orchestrated by Bun.

-   **Full Build:** Run `BUILD.cmd` in the root or `bin/build.cmd`. This builds both `tgui` and compiles the DM code.
-   **Build tgui Only:** `bin/tgui-build.cmd` or `bun run tgui:build` inside the `/tgui` directory.
-   **Build DM Only:** The build scripts generally handle this, but it targets `roguetown.dme`.

### Running the Server

-   **Local Server:** Use `bin/server.cmd` to start the game server via `DreamDaemon`.
-   **Port:** Default port is usually `1337`.

### Testing & Quality Control

-   **Run Tests:** `bin/test.cmd` executes both DM unit tests and tgui tests.
-   **Linting (DM):** Configured via `SpacemanDMM.toml`. Uses `dreamchecker`.
-   **Linting (tgui):** Run `bun run tgui:lint` in the `/tgui` directory.
-   **Formatting:** `tgui` uses Prettier (`bun run tgui:prettier`).

### Contribution Standards

-   **Code Cleanliness:** Do not comment out code; remove it.
-   **Documentation:** All PRs must have documented changes and test evidence in the description.
-   **Safety:** No slurs are permitted in code or comments.
-   **Modular Content:** Prefer adding large map-specific or optional features to `modular_*` directories to keep the core clean.

## Important Files

-   `roguetown.dme`: The main BYOND project file.
-   `code/_compile_options.dm`: Critical for toggling debug/testing modes.
-   `SpacemanDMM.toml`: Linter and code standard configuration.
-   `tgui/package.json`: Dependency and script management for the modern UI.
-   `dependencies.sh`: External dependency definitions.
