#import <Cocoa/Cocoa.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN
// Vision boxes use normalized image coordinates, with the origin at bottom left.
NSArray<NSDictionary *> * _Nullable TCImageTextRegions(NSData *image, NSError **error);
// The helper makes exactly one direct Vision request before exiting.
NSArray<NSDictionary *> * _Nullable TCImageTextRegionsDirect(NSData *image, NSError **error);
NSRect TCImageTranslationPanelFrame(NSRect image, NSRect visible, NSRect *toolbar);
NSData * _Nullable TCRenderImageTranslations(NSData *image, NSArray<NSDictionary *> *regions,
                                           NSDictionary<NSString *, NSString *> *translations, NSError **error);
typedef void (*TCImageTranslationCompletion)(const uint8_t * _Nullable bytes, size_t length, int32_t action);
// action: 0 return to native editor, 1 copy translated PNG, 2 save translated PNG.
// Callback bytes are valid only for the duration of the callback.
// Pass NULL regions to show the panel immediately and recognize in the background.
void TCShowImageTranslation(const void *image, const void * _Nullable regions, const void *owner,
                            double x, double y, double width, double height, TCImageTranslationCompletion completion);
void TCDismissImageTranslation(void);
NS_ASSUME_NONNULL_END
