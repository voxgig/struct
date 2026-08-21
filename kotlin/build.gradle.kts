plugins {
    kotlin("jvm") version "2.2.0"
    // Code quality
    id("io.gitlab.arturbosch.detekt") version "1.23.8"
    id("org.jlleitschuh.gradle.ktlint") version "12.1.2"
    // Maven Central publishing via the Sonatype Central Portal (+ GPG signing).
    id("com.vanniktech.maven.publish") version "0.37.0"
}

group = "com.voxgig"
version = "0.1.0"

repositories {
    mavenCentral()
}

dependencies {
    // Gson is used ONLY by the test harness (assertion diffs). The library
    // proper has no third-party JSON dependency.
    testImplementation("com.google.code.gson:gson:2.11.0")
    testImplementation(kotlin("test"))
}

// The corpus runner is voxgig/omni, consumed as a local checkout - it is not
// published to Maven Central. $OMNI_HOME first, then sibling paths, taking the
// first directory that carries spec/fib.json.
//
// Its classes reach the TESTS and nowhere else: `gradle jar` and anything
// published from src/main/kotlin are untouched (register 4.13).
val omniHome: String? =
    listOfNotNull(
        System.getenv("OMNI_HOME"),
        "$rootDir/../../omni",
        "$rootDir/../../../omni",
        "/workspace/omni",
        "/home/user/omni",
    ).firstOrNull { File(it, "spec/fib.json").isFile }

// A missing checkout must not break `gradle jar` or `gradle compileKotlin` -
// the library build never needs omni (register 4.13). So the path stays
// nominal here and the failure is raised by the tasks that actually need it,
// below, where the message can say what to do.
val omniSrc: String = "${omniHome ?: "$rootDir/build/no-omni-checkout"}/kotlin/src"

// Its own source set rather than extra test sources, so the style checks below
// see this port's code and nothing else: omni's style is omni's business.
val omni: SourceSet by sourceSets.creating {
    java.setSrcDirs(emptyList<String>())
    kotlin.setSrcDirs(listOf(omniSrc))
}

dependencies {
    testImplementation(omni.output)
}

// ktlint registers a check task per source set; omni gets none.
tasks.matching { it.name.startsWith("ktlintOmni") }.configureEach { enabled = false }

tasks.matching { it.name in setOf("compileOmniKotlin", "compileTestKotlin", "test") }
    .configureEach {
        doFirst {
            if (null == omniHome) {
                error(
                    "struct: voxgig/omni checkout not found - set OMNI_HOME.\n" +
                        "  The tests run on the shared runner; the library itself does not.\n" +
                        "  git clone https://github.com/voxgig/omni ../../omni",
                )
            }
        }
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
    // This port's sources only. omni's join the test source set so they
    // compile with the tests; their style is omni's business, not this port's.
    source.setFrom(files("src/main/kotlin", "src/test/kotlin"))
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

// ---- Maven Central publishing via the Sonatype Central Portal ----
// OSSRH/Nexus staging was retired 2025-06-30, so publish through the Central
// Portal with the vanniktech plugin. It builds the sources + javadoc jars,
// signs every artifact, uploads the bundle, and (automaticRelease) releases it.
// Auth comes from ORG_GRADLE_PROJECT_* env vars at release time (see Makefile):
//   mavenCentralUsername / mavenCentralPassword   Portal user token
//   signingInMemoryKey / signingInMemoryKeyPassword   ASCII-armored GPG key
// publishToMavenLocal needs no key (signing only applies to the remote publish).
mavenPublishing {
    publishToMavenCentral(automaticRelease = true)
    signAllPublications()
    coordinates("com.voxgig", "struct-kotlin", version.toString())
    pom {
        name.set("voxgig-struct-kotlin")
        description.set(
            "Voxgig Struct — utilities for transforming JSON-like data structures (Kotlin port).",
        )
        url.set("https://github.com/voxgig/struct")
        licenses {
            license {
                name.set("MIT License")
                url.set("https://opensource.org/licenses/MIT")
                distribution.set("repo")
            }
        }
        developers {
            developer {
                id.set("voxgig")
                name.set("Voxgig")
                organization.set("Voxgig")
                organizationUrl.set("https://voxgig.com")
            }
        }
        scm {
            connection.set("scm:git:https://github.com/voxgig/struct.git")
            developerConnection.set("scm:git:git@github.com:voxgig/struct.git")
            url.set("https://github.com/voxgig/struct")
        }
    }
}
