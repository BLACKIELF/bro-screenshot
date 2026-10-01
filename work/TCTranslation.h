#ifndef TC_TRANSLATION_H
#define TC_TRANSLATION_H
/* Main thread only. Creates a normal result window, never a capture overlay.
 * Translation starts only after the user presses the window's Translate button. */
void TCShowRecognizedText(const char *utf8Text);
#endif
