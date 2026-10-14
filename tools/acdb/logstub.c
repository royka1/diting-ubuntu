#include <stdio.h>
#include <stdarg.h>
#include <stdint.h>
uint32_t ar_log_lvl = 0x1 | 0x2; /* errors + warnings; set AR_LOG env to override */
void ar_log_init(void) {}
void ar_log_deinit(void) {}
void ar_set_log_level(uint32_t l) { ar_log_lvl = l; }
void ar_log(uint32_t level, const char *tag, const char *file, const char *fn, const uint32_t line, const char *fmt, ...)
{
	va_list ap; va_start(ap, fmt);
	fprintf(stderr, "[%s] %s:%u ", tag, fn, line); vfprintf(stderr, fmt, ap); fputc('\n', stderr);
	va_end(ap);
}
