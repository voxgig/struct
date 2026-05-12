.PHONY: inspect build test lint clean reset

GRADLE ?= ./gradlew

inspect:
	@echo "Java version:"
	@java -version 2>&1 | head -1
	@echo ""
	@$(GRADLE) --version | grep -E 'Gradle|Kotlin'

build:
	$(GRADLE) compileKotlin

test:
	$(GRADLE) test

# Code quality: detekt (static analysis) + ktlint (style).
lint:
	$(GRADLE) detekt ktlintCheck

clean:
	$(GRADLE) clean

reset: clean
	rm -rf .gradle build
