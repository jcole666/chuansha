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

// 统一所有子模块（含第三方插件）的 Java/Kotlin JVM target，
// 解决 tflite_flutter 插件 Java=11 / Kotlin=21 不一致导致的构建失败
subprojects {
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = "17"
        targetCompatibility = "17"
    }
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

// 统一抬高所有子模块的 compileSdk。
//
// 背景：部分第三方插件在自己的 android/build.gradle 里写死了偏低的 compileSdk，
// 而它们依赖的 androidx 库要求更高的 compileSdk，构建会在
// ':xxx:checkDebugAarMetadata' 处报 "N issues were found when checking AAR metadata"。
// 例如 onnxruntime 1.4.1 写死 compileSdkVersion 33，但其依赖
// androidx.fragment 1.7.1 / androidx.activity 1.8.1 等要求 >= 34。
//
// 这里只"抬高"不"降低"：低于 36 的一律设为 36（= Flutter 当前默认
// flutter.compileSdkVersion，且本机已安装 android-36）。
// compileSdk 只是"用哪个 SDK 编译"，向前兼容，不影响 minSdk/targetSdk 的运行时行为。
subprojects {
    afterEvaluate {
        when {
            plugins.hasPlugin("com.android.library") ->
                extensions.configure<com.android.build.api.dsl.LibraryExtension>("android") {
                    if ((compileSdk ?: 0) < 36) compileSdk = 36
                }
            plugins.hasPlugin("com.android.application") ->
                extensions.configure<com.android.build.api.dsl.ApplicationExtension>("android") {
                    if ((compileSdk ?: 0) < 36) compileSdk = 36
                }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
