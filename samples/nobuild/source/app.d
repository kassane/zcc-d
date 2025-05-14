import std.stdio : writeln;
import std.string : fromStringz, toStringz;

void main() @trusted
{
    const(char)* str = get_string();
    writeln(str.fromStringz);
    process_string("Test string from D");

    int* arr = create_array(5);
    delete_array(arr);

    FFIPoint* point = create_point(1.0, 2.0);
    writeln("Point coordinates: ", point.x, ", ", point.y);
    delete_point(point);

    CallbackFn lambda = (int val) { writeln("Callback received: ", val); };
    register_callback(lambda);

    void* obj = create_complex_object();
    set_complex_value(obj, 100);
    writeln("Complex object value: ", get_complex_value(obj));
    delete_complex_object(obj);
}

extern (C):
// String handling
const(char)* get_string();
void process_string(const(char)* input);

// Array handling
int* create_array(size_t size);
void delete_array(int* arr);

// Struct example for FFI
struct FFIPoint
{
    double x;
    double y;
}

FFIPoint* create_point(double x, double y);
void delete_point(FFIPoint* point);

// Callback example
alias CallbackFn = void function(int);
void register_callback(CallbackFn callback);

// C++ class wrapper
void* create_complex_object();
void delete_complex_object(void* obj);
void set_complex_value(void* obj, int value);
int get_complex_value(void* obj);
