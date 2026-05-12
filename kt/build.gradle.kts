plugins {
    kotlin("jvm") version "2.2.0"
    // Code quality
    id("io.gitlab.arturbosch.detekt") version "1.23.8"
    id("org.jlleitschuh.gradle.ktlint") version "12.1.2"
}

group = "voxgig.struct"
version = "0.0.10"

repositories {
    mavenCentral()
}

dependencies {
    implementation("com.google.code.gson:gson:2.11.0")
    testImplementation(kotlin("test"))
}

tasks.test {
    useJUnitPlatform()
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

tasks.withType<JavaCompile>().configureEach {
    options.release.set(17)
}

// ---- Code quality: detekt (static analysis) + ktlint (style) ----
detekt {
    buildUponDefaultConfig = true
    config.setFrom(files("$rootDir/detekt.yml"))
    basePath = rootDir.absolutePath
}

ktlint {
    ignoreFailures.set(false)
}

// Convenience aggregate task: `gradle lint`
tasks.register("lint") {
    group = "verification"
    description = "Runs detekt and ktlint."
    dependsOn("detekt", "ktlintCheck")
}
