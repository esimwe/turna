import org.gradle.api.tasks.compile.JavaCompile

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
    configurations.configureEach {
        resolutionStrategy.dependencySubstitution {
            substitute(module("com.github.davidliu:audioswitch"))
                .using(module("com.twilio:audioswitch:1.2.4"))
                .because(
                    "flutter_webrtc points at an old JitPack coordinate; use the official Maven Central artifact for all subprojects.",
                )
        }
    }
}
subprojects {
    tasks.withType<JavaCompile>().configureEach {
        options.isWarnings = false
        options.compilerArgs.addAll(
            listOf(
                "-nowarn",
                "-Xlint:-options",
                "-Xlint:-deprecation",
                "-Xlint:-unchecked",
            ),
        )
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
