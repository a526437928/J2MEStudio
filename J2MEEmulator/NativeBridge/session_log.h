#ifndef STUDIO_SESSION_LOG_H
#define STUDIO_SESSION_LOG_H
int studio_log_begin(const char *path);
void studio_log_end(void);
void studio_log_flush(void);
#endif
