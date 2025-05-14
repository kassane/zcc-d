import c.ffi;

// import core.stdc.stdint;
// import core.stdc.stdlib;
// import core.stdc.string;

// extern (C)
// {
//     struct FFIData
//     {
//         int32_t id;
//         char[64] name;
//         double value;
//     }

//     FFIData* create_data(int32_t id, const(char)* name, double value);
//     void free_data(FFIData* data);

//     alias CallbackFunc = void function(int32_t status);
//     void register_callback(CallbackFunc callback);

//     int32_t sum_array(int32_t* array, size_t length);
//     char* reverse_string(const(char)* input);
// }

void main() @trusted
{
    // Test creating and using FFIData
    auto data = create_data(1, "Test".ptr, 3.14);
    printf("Created data: id=%d, name=%s, value=%f\n", data.id, data.name.ptr, data.value);
    free_data(data);

    // Test callback registration
    register_callback(callback);

    // Test array handling
    int[5] arr = [1, 2, 3, 4, 5];
    auto sum = sum_array(arr.ptr, arr.length);
    printf("Sum of array: %d\n", sum);

    // Test string handling
    auto reversed = reverse_string("Hello from D!");
    printf("Reversed string: %s\n", reversed);
    free(reversed);
}

extern (C)
{
    alias CallbackFn = void function(int);
    CallbackFn callback = (int status = 42) {
        printf("Callback received status: %d\n", status);
    };
}
