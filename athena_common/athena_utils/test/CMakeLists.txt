ament_add_gtest(
  athena_lifecycle_test athena_lifecycle_test.cpp
  TIMEOUT 120
)
ament_target_dependencies(athena_lifecycle_test ${dependencies})
target_link_libraries(athena_lifecycle_test ${library_name})
