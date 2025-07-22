pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        mavenLocal()
        maven {
            url = uri("https://maven.pkg.github.com/Polkabind/polkabind-kotlin-pkg")
            credentials {
                username = "YOUR_GITHUB_USERNAME"
                password = System.getenv("GITHUB_TOKEN")
            }
        }
        google()
        mavenCentral()
    }
}

rootProject.name = "PolkabindExample"
include(":app")
