#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>
uid_t ccw_audit_euid(const void *bytes, size_t length);

int32_t ccw_audit_pid(const void *bytes, size_t length);
int32_t ccw_owns_loopback_socket(int32_t pid, uint16_t local_port, uint16_t remote_port, int32_t listening);
