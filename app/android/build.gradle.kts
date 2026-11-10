allprojects {
    repositories {
        google()
        mavenCentral()
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// Windows: Kotlin incremental compilation fails with "Could not close
// incremental caches" when the project and the pub cache are on different
// drives. gradle.properties sets kotlin.incremental=false; this also forces it
// on every Kotlin compile task, because each Flutter plugin brings its own
// Kotlin Gradle plugin version (so this uses reflection, not typed APIs).
subprojects {
    tasks.configureEach {
        if (name.startsWith("compile") && name.endsWith("Kotlin")) {
            runCatching {
                javaClass.getMethod("setIncremental", Boolean::class.javaPrimitiveType).invoke(this, false)
            }
        }
    }
}
