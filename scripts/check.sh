#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
swift run AdaChecks
mkdir -p .build/checks
swiftc -parse-as-library Sources/Ada/IslandButtonStyle.swift Sources/Ada/FileShelf.swift Tests/Standalone/ShelfChecks.swift -o .build/checks/AdaShelfChecks
.build/checks/AdaShelfChecks
swiftc -parse-as-library Sources/Ada/IslandButtonStyle.swift Sources/Ada/TeleprompterView.swift Tests/Standalone/PrompterChecks.swift -o .build/checks/AdaPrompterChecks
.build/checks/AdaPrompterChecks
swiftc -parse-as-library Sources/Ada/IslandButtonStyle.swift Sources/Ada/SystemMonitor.swift Tests/Standalone/SystemChecks.swift -o .build/checks/AdaSystemChecks
.build/checks/AdaSystemChecks
swiftc -parse-as-library Sources/Ada/IslandButtonStyle.swift Sources/Ada/AssistantView.swift Tests/Standalone/AssistantChecks.swift -o .build/checks/AdaAssistantChecks
.build/checks/AdaAssistantChecks
swiftc -parse-as-library Sources/Ada/IslandButtonStyle.swift Sources/Ada/CloudWorkspaceView.swift Tests/Standalone/CloudChecks.swift -o .build/checks/AdaCloudChecks
.build/checks/AdaCloudChecks
swiftc -parse-as-library Sources/Ada/IslandButtonStyle.swift Sources/Ada/DashboardTiles.swift Tests/Standalone/DashboardTilesChecks.swift -o .build/checks/AdaDashboardTilesChecks
.build/checks/AdaDashboardTilesChecks
swiftc -parse-as-library Sources/Ada/NowPlayingStore.swift Tests/Standalone/NowPlayingChecks.swift -o .build/checks/AdaNowPlayingChecks
.build/checks/AdaNowPlayingChecks
swiftc -parse-as-library Sources/Ada/LoginItemStore.swift Tests/Standalone/LoginItemChecks.swift -o .build/checks/AdaLoginItemChecks
.build/checks/AdaLoginItemChecks
