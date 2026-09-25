plugins { kotlin("multiplatform") }
kotlin {
    iosSimulatorArm64 {
        binaries.framework { baseName = "Shared" }
    }
}
