
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  int32_t id;
  char name[64];
  double value;
} FFIData;

// Function that can be called from other languages
extern FFIData *create_data(int32_t id, const char *name, double value) {
  FFIData *data = (FFIData *)malloc(sizeof(FFIData));
  data->id = id;
  strncpy(data->name, name, 63);
  data->name[63] = '\0';
  data->value = value;
  return data;
}

// Function to free memory allocated for FFIData
extern void free_data(FFIData *data) { free(data); }

// Example of callback function type
typedef void (*CallbackFunc)(int32_t status);

// Function that accepts a callback
extern void register_callback(CallbackFunc callback) {
  // Store callback for later use
  callback(200);
}

// Array handling example
extern int32_t sum_array(int32_t *array, size_t length) {
  int32_t sum = 0;
  for (size_t i = 0; i < length; i++) {
    sum += array[i];
  }
  return sum;
}

// String handling example
extern char *reverse_string(const char *input) {
  size_t len = strlen(input);
  char *result = (char *)malloc(len + 1);
  for (size_t i = 0; i < len; i++) {
    result[i] = input[len - 1 - i];
  }
  result[len] = '\0';
  return result;
}
