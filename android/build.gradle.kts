allprojects {
    // Plugin subprojects (cloud_firestore, firebase_core, image_picker, ...) ship their own
    // `buildscript { repositories { google(); mavenCentral() } }` blocks that pin a specific
    // Android Gradle Plugin. Those blocks bypass pluginManagement's repositories, so the
    // mirrors configured below must be injected here too, otherwise the build stalls trying
    // to reach Google Maven directly for artifacts such as AGP 8.1.2.
    buildscript {
        repositories {
            maven { url = uri("https://maven.aliyun.com/repository/google") }
            maven { url = uri("https://maven.aliyun.com/repository/central") }
            maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
            maven { url = uri("https://maven.aliyun.com/repository/public") }
            google()
            mavenCentral()
        }
    }

    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Plugin subprojects (cloud_firestore, firebase_core, ...) each apply their own Android
// Gradle Plugin version, so each one defaults to a different Build Tools revision
// (33.0.1, 34.0.0, ...). Only 33.0.0, 36.0.0, 36.1.0 and 37.0.0 are installed here, and
// AGP can't fetch the rest because dl.google.com is unreachable. Pin every Android module
// to one installed revision. Reflection is used because AGP classes are not on this
// script's compile classpath.
val installedBuildToolsVersion = "36.0.0"

subprojects {
    // evaluationDependsOn(":app") above may already have evaluated :app, in which case
    // afterEvaluate() would throw, so only defer when the project is still pending.
    fun pinBuildTools() {
        val androidExtension = extensions.findByName("android") ?: return
        runCatching {
            androidExtension.javaClass
                .getMethod("setBuildToolsVersion", String::class.java)
                .invoke(androidExtension, installedBuildToolsVersion)
        }
    }

    if (state.executed) {
        pinBuildTools()
    } else {
        afterEvaluate { pinBuildTools() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
