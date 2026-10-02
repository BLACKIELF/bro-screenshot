#import <Cocoa/Cocoa.h>
#import "../TCImageTranslation.h"
#include <assert.h>

int main(void) {
    @autoreleasepool {
        NSArray<NSValue *> *screens = @[[NSValue valueWithRect:NSMakeRect(0,0,1440,900)],
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
        // Tall selections leave no room above/below, but can leave room on
        // either side. Controls must use that room before covering the image.
        NSRect tall[] = {NSMakeRect(0,0,400,900), NSMakeRect(1040,0,400,900),
                         NSMakeRect(-900,0,200,1440)};
        for (int i=0;i<3;i++) {
            NSRect screen = i == 2 ? screens[1].rectValue : screens[0].rectValue;
            NSRect toolbar, panel = TCImageTranslationPanelFrame(tall[i],screen,&toolbar);
            assert(NSContainsRect(screen,toolbar) && NSContainsRect(panel,tall[i]));
            if (NSIntersectsRect(toolbar,tall[i])) {
                fprintf(stderr,"toolbar covers a tall selection despite free side space: case=%d\n",i);
                return 1;
            }
        }
        NSRect toolbar;
        TCImageTranslationPanelFrame(NSMakeRect(400,0,600,900),screens[0].rectValue,&toolbar);
        NSRect overlap = NSIntersectionRect(toolbar,NSMakeRect(400,0,600,900));
        // When it cannot fit completely outside, do not cover its entire width.
        assert(overlap.size.width <= 130 && overlap.size.height <= 116);
        puts("PASS inline preview: preserves image position, toolbar visible at edges, negative-origin and narrow displays, tall selections use free sides, unavoidable overlap minimized.");
    }
    return 0;
}
