.PHONY: inspect build test clean reset

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

clean:
	mvn -q clean

reset: clean
