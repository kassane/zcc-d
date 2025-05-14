
#include <cstdint>
#include <string>

extern "C" {
// String handling
const char *get_string() { return "Hello from C++"; }

void process_string(const char *input) { std::string cpp_str(input); }

// Array handling
int32_t *create_array(size_t size) { return new int32_t[size]; }

void delete_array(int32_t *arr) { delete[] arr; }

struct FFIPoint {
  double x;
  double y;
};

FFIPoint *create_point(double x, double y) {
  auto *point = new FFIPoint{x, y};
  return point;
}

void delete_point(FFIPoint *point) { delete point; }

// Callback example
typedef void (*CallbackFn)(int);

void register_callback(CallbackFn callback) { callback(42); }
}

// C++ class with C wrapper
class ComplexObject {
public:
  ComplexObject() : value_(0) {}
  void setValue(int v) { value_ = v; }
  int getValue() const { return value_; }

private:
  int value_;
};

extern "C" {
void *create_complex_object() { return new ComplexObject(); }

void delete_complex_object(void *obj) {
  delete static_cast<ComplexObject *>(obj);
}

void set_complex_value(void *obj, int value) {
  static_cast<ComplexObject *>(obj)->setValue(value);
}

int get_complex_value(void *obj) {
  return static_cast<ComplexObject *>(obj)->getValue();
}
}
