.PHONY: inspect build test lint checkstyle spotbugs clean reset

inspect:
	@echo "Java version:"
	@java -version 2>&1 | head -1
	@echo ""
	@echo "Maven version:"
	@mvn -v | head -1

build:
	mvn -q -DskipTests compile

test:
	mvn -q test

# Code quality: Checkstyle (style) + SpotBugs (bug pattern detection).
lint:
	mvn -q -DskipTests compile checkstyle:check spotbugs:check

checkstyle:
	mvn -q checkstyle:check

spotbugs:
	mvn -q -DskipTests compile spotbugs:check

clean:
	mvn -q clean

reset: clean
