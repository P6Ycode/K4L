#ifdef __cplusplus
extern "C" {
#endif
void SCIInstallMessageSeenButtonHooksIfNeeded(void);
void SCIInstallStorySeenButtonHooksIfNeeded(void);
void SCIInstallStoryMentionsButtonHooksIfNeeded(void);
void SCIInstallDirectVisualSeenButtonHooksIfNeeded(void);
#ifdef __cplusplus
}
#endif

void SCIInstallSeenButtonHooksIfNeeded(void) {
    SCIInstallMessageSeenButtonHooksIfNeeded();
    SCIInstallStorySeenButtonHooksIfNeeded();
    SCIInstallStoryMentionsButtonHooksIfNeeded();
    SCIInstallDirectVisualSeenButtonHooksIfNeeded();
}
