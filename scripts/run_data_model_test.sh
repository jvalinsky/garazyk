#!/bin/bash
# Run only the data model fixtures test

./build/tests/AllTests AtprotoInteropFixturesTests/testInteropDataModelFixtures 2>&1 | grep -A 50 "testInteropDataModelFixtures"
