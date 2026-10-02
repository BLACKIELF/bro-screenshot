#import <Cocoa/Cocoa.h>
#import "../TCImageTranslation.h"
#include <assert.h>

int main(void) {
    @autoreleasepool {
        NSArray *screens = @[[NSValue valueWithRect:NSMakeRect(0,0,1440,900)],
                             [NSValue valueWithRect:NSMakeRect(-900,0,900,1440)],
                             [NSValue valueWithRect:NSMakeRect(0,-900,450,900)]];
        for (NSValue *value in screens) {
            NSRect screen = value.rectValue;
            NSRect cases[] = {NSMakeRect(screen.origin.x+20,screen.origin.y+200,300,140),
                NSMakeRect(screen.origin.x+10,screen.origin.y,screen.size.width-20,50),
                NSMakeRect(screen.origin.x,screen.origin.y,screen.size.width,screen.size.height)};
            for (int i=0;i<3;i++) {
                NSRect toolbar, panel = TCImageTranslationPanelFrame(cases[i],screen,&toolbar);
                assert(NSContainsRect(panel,cases[i]) && NSContainsRect(panel,toolbar));
                assert(NSContainsRect(screen,toolbar));
                // Converting the image into the composite view and back never
                // moves its screen position, including negative monitor origins.
                NSRect local=NSOffsetRect(cases[i],-panel.origin.x,-panel.origin.y);
                assert(NSEqualRects(NSOffsetRect(local,panel.origin.x,panel.origin.y),cases[i]));
            }
        }
        puts("PASS inline preview: preserves image position, toolbar visible at edges, negative-origin and narrow displays.");
    }
    return 0;
}
