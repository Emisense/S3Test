/*
  ==============================================================================

   This file is part of the JUCE library - "Jules' Utility Class Extensions"
   Copyright 2004-11 by Raw Material Software Ltd.

  ------------------------------------------------------------------------------

   JUCE can be redistributed and/or modified under the terms of the GNU General
   Public License (Version 2), as published by the Free Software Foundation.
   A copy of the license is included in the JUCE distribution, or can be found
   online at www.gnu.org/licenses.

   JUCE is distributed in the hope that it will be useful, but WITHOUT ANY
   WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
   A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  ------------------------------------------------------------------------------

   To release a closed-source product which uses JUCE, commercial licenses are
   available: visit www.rawmaterialsoftware.com/juce for more information.

  ==============================================================================
*/

typedef void (*AppFocusChangeCallback)();
extern AppFocusChangeCallback appFocusChangeCallback;
typedef bool (*CheckEventBlockedByModalComps) (NSEvent*);
extern CheckEventBlockedByModalComps isEventBlockedByModalComps;

//==============================================================================
#if ! (defined (MAC_OS_X_VERSION_10_7) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_7)
} // (juce namespace)

@interface NSEvent (JuceDeviceDelta)
 - (CGFloat) scrollingDeltaX;
 - (CGFloat) scrollingDeltaY;
 - (BOOL) hasPreciseScrollingDeltas;
 - (BOOL) isDirectionInvertedFromDevice;
@end

namespace juce {
#endif

//==============================================================================
class NSViewComponentPeer  : public ComponentPeer
{
public:
    NSViewComponentPeer (Component* const comp, const int windowStyleFlags, NSView* viewToAttachTo)
        : ComponentPeer (comp, windowStyleFlags),
          window (nil),
          view (nil),
          isSharedWindow (viewToAttachTo != nil),
          fullScreen (false),
          insideDrawRect (false),
         #if USE_COREGRAPHICS_RENDERING
          usingCoreGraphics (true),
         #else
          usingCoreGraphics (false),
         #endif
          recursiveToFrontCall (false),
          isZooming (false),
          textWasInserted (false),
          notificationCenter (nil)
    {
        appFocusChangeCallback = appFocusChanged;
        isEventBlockedByModalComps = checkEventBlockedByModalComps;

        NSRect r = NSMakeRect (0, 0, (CGFloat) component->getWidth(), (CGFloat) component->getHeight());

        view = [createViewInstance() initWithFrame: r];
        setOwner (view, this);

        [view registerForDraggedTypes: getSupportedDragTypes()];

        notificationCenter = [NSNotificationCenter defaultCenter];

        [notificationCenter  addObserver: view
                                selector: @selector (frameChanged:)
                                    name: NSViewFrameDidChangeNotification
                                  object: view];

        if (! isSharedWindow)
            [notificationCenter  addObserver: view
                                    selector: @selector (frameChanged:)
                                        name: NSWindowDidMoveNotification
                                      object: window];

        [view setPostsFrameChangedNotifications: YES];

        if (isSharedWindow)
        {
            window = [viewToAttachTo window];
            [viewToAttachTo addSubview: view];
        }
        else
        {
            r.origin.x = (CGFloat) component->getX();
            r.origin.y = (CGFloat) component->getY();
            r.origin.y = [[[NSScreen screens] objectAtIndex: 0] frame].size.height - (r.origin.y + r.size.height);

            window = [createWindowInstance() initWithContentRect: r
                                                       styleMask: getNSWindowStyleMask (windowStyleFlags)
                                                         backing: NSBackingStoreBuffered
                                                           defer: YES];

            setOwner (window, this);
            [window orderOut: nil];
           #if defined (MAC_OS_X_VERSION_10_6) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_6
            [window setDelegate: (id<NSWindowDelegate>) window];
           #else
            [window setDelegate: window];
           #endif
            [window setOpaque: component->isOpaque()];
            [window setHasShadow: ((windowStyleFlags & windowHasDropShadow) != 0)];

            if (component->isAlwaysOnTop())
                [window setLevel: NSFloatingWindowLevel];

            [window setContentView: view];
            [window setAutodisplay: YES];
            [window setAcceptsMouseMovedEvents: YES];

            // We'll both retain and also release this on closing because plugin hosts can unexpectedly
            // close the window for us, and also tend to get cause trouble if setReleasedWhenClosed is NO.
            [window setReleasedWhenClosed: YES];
            [window retain];

            [window setExcludedFromWindowsMenu: (windowStyleFlags & windowIsTemporary) != 0];
            [window setIgnoresMouseEvents: (windowStyleFlags & windowIgnoresMouseClicks) != 0];

           #if defined (MAC_OS_X_VERSION_10_7) && (MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7)
            if ((windowStyleFlags & (windowHasMaximiseButton | windowHasTitleBar)) == (windowHasMaximiseButton | windowHasTitleBar))
                [window setCollectionBehavior: NSWindowCollectionBehaviorFullScreenPrimary];
           #endif
        }

        const float alpha = component->getAlpha();
        if (alpha < 1.0f)
            setAlpha (alpha);

        setTitle (component->getName());
    }

    ~NSViewComponentPeer()
    {
        [notificationCenter removeObserver: view];
        setOwner (view, nullptr);
        [view removeFromSuperview];
        [view release];

        if (! isSharedWindow)
        {
            setOwner (window, nullptr);
            [window close];
            [window release];
        }
    }

    //==============================================================================
    void* getNativeHandle() const    { return view; }

    void setVisible (bool shouldBeVisible)
    {
        if (isSharedWindow)
        {
            [view setHidden: ! shouldBeVisible];
        }
        else
        {
            if (shouldBeVisible)
            {
                [window orderFront: nil];
                handleBroughtToFront();
            }
            else
            {
                [window orderOut: nil];
            }
        }
    }

    void setTitle (const String& title)
    {
        JUCE_AUTORELEASEPOOL

        if (! isSharedWindow)
            [window setTitle: juceStringToNS (title)];
    }

    void setPosition (int x, int y)
    {
        setBounds (x, y, component->getWidth(), component->getHeight(), false);
    }

    void setSize (int w, int h)
    {
        setBounds (component->getX(), component->getY(), w, h, false);
    }

    void setBounds (int x, int y, int w, int h, bool isNowFullScreen)
    {
        fullScreen = isNowFullScreen;

        NSRect r = NSMakeRect ((CGFloat) x, (CGFloat) y, (CGFloat) jmax (0, w), (CGFloat) jmax (0, h));

        if (isSharedWindow)
        {
            r.origin.y = [[view superview] frame].size.height - (r.origin.y + r.size.height);

            if ([view frame].size.width != r.size.width
                 || [view frame].size.height != r.size.height)
            {
                [view setNeedsDisplay: true];
            }

            [view setFrame: r];
        }
        else
        {
            r.origin.y = [[[NSScreen screens] objectAtIndex: 0] frame].size.height - (r.origin.y + r.size.height);

            [window setFrame: [window frameRectForContentRect: r]
                     display: true];
        }
    }

    Rectangle<int> getBounds (const bool global) const
    {
        NSRect r = [view frame];
        NSWindow* window = [view window];

        if (global && window != nil)
        {
            r = [[view superview] convertRect: r toView: nil];

           #if defined (MAC_OS_X_VERSION_10_7) && MAC_OS_X_VERSION_MIN_ALLOWED >= MAC_OS_X_VERSION_10_7
            r = [window convertRectToScreen: r];
           #else
            r.origin = [window convertBaseToScreen: r.origin];
           #endif

            r.origin.y = [[[NSScreen screens] objectAtIndex: 0] frame].size.height - r.origin.y - r.size.height;
        }
        else
        {
            r.origin.y = [[view superview] frame].size.height - r.origin.y - r.size.height;
        }

        return Rectangle<int> (convertToRectInt (r));
    }

    Rectangle<int> getBounds() const
    {
        return getBounds (! isSharedWindow);
    }

    Point<int> getScreenPosition() const
    {
        return getBounds (true).getPosition();
    }

    Point<int> localToGlobal (const Point<int>& relativePosition)
    {
        return relativePosition + getScreenPosition();
    }

    Point<int> globalToLocal (const Point<int>& screenPosition)
    {
        return screenPosition - getScreenPosition();
    }

    void setAlpha (float newAlpha)
    {
        if (! isSharedWindow)
        {
            [window setAlphaValue: (CGFloat) newAlpha];
        }
        else
        {
           #if defined (MAC_OS_X_VERSION_10_5) && MAC_OS_X_VERSION_MIN_ALLOWED >= MAC_OS_X_VERSION_10_5
            [view setAlphaValue: (CGFloat) newAlpha];
           #else
            if ([view respondsToSelector: @selector (setAlphaValue:)])
            {
                // PITA dynamic invocation for 10.4 builds..
                NSInvocation* inv = [NSInvocation invocationWithMethodSignature: [view methodSignatureForSelector: @selector (setAlphaValue:)]];
                [inv setSelector: @selector (setAlphaValue:)];
                [inv setTarget: view];
                CGFloat cgNewAlpha = (CGFloat) newAlpha;
                [inv setArgument: &cgNewAlpha atIndex: 2];
                [inv invoke];
            }
           #endif
        }
    }

    void setMinimised (bool shouldBeMinimised)
    {
        if (! isSharedWindow)
        {
            if (shouldBeMinimised)
                [window miniaturize: nil];
            else
                [window deminiaturize: nil];
        }
    }

    bool isMinimised() const
    {
        return [window isMiniaturized];
    }

    void setFullScreen (bool shouldBeFullScreen)
    {
        if (! isSharedWindow)
        {
            Rectangle<int> r (lastNonFullscreenBounds);

            if (isMinimised())
                setMinimised (false);

            if (fullScreen != shouldBeFullScreen)
            {
                if (shouldBeFullScreen && hasNativeTitleBar())
                {
                    fullScreen = true;
                    [window performZoom: nil];
                }
                else
                {
                    if (shouldBeFullScreen)
                        r = component->getParentMonitorArea();

                    // (can't call the component's setBounds method because that'll reset our fullscreen flag)
                    if (r != getComponent()->getBounds() && ! r.isEmpty())
                        setBounds (r.getX(), r.getY(), r.getWidth(), r.getHeight(), shouldBeFullScreen);
                }
            }
        }
    }

    bool isFullScreen() const
    {
        return fullScreen;
    }

    bool contains (const Point<int>& position, bool trueIfInAChildWindow) const
    {
        if (! (isPositiveAndBelow (position.getX(), component->getWidth())
                && isPositiveAndBelow (position.getY(), component->getHeight())))
            return false;

        NSRect frameRect = [view frame];

        NSView* v = [view hitTest: NSMakePoint (frameRect.origin.x + position.getX(),
                                                frameRect.origin.y + frameRect.size.height - position.getY())];

        if (trueIfInAChildWindow)
            return v != nil;

        return v == view;
    }

    BorderSize<int> getFrameSize() const
    {
        BorderSize<int> b;

        if (! isSharedWindow)
        {
            NSRect v = [view convertRect: [view frame] toView: nil];
            NSRect w = [window frame];

            b.setTop ((int) (w.size.height - (v.origin.y + v.size.height)));
            b.setBottom ((int) v.origin.y);
            b.setLeft ((int) v.origin.x);
            b.setRight ((int) (w.size.width - (v.origin.x + v.size.width)));
        }

        return b;
    }

    void updateFullscreenStatus()
    {
        if (hasNativeTitleBar())
        {
            const Rectangle<int> screen (getFrameSize().subtractedFrom (component->getParentMonitorArea()));
            const Rectangle<int> window (component->getScreenBounds());

            fullScreen = window.expanded (2, 2).contains (screen);
        }
    }

    bool hasNativeTitleBar() const
    {
        return (getStyleFlags() & windowHasTitleBar) != 0;
    }

    bool setAlwaysOnTop (bool alwaysOnTop)
    {
        if (! isSharedWindow)
            [window setLevel: alwaysOnTop ? NSFloatingWindowLevel
                                          : NSNormalWindowLevel];
        return true;
    }

    void toFront (bool makeActiveWindow)
    {
        if (isSharedWindow)
            [[view superview] addSubview: view
                              positioned: NSWindowAbove
                              relativeTo: nil];

        if (window != nil && component->isVisible())
        {
            if (makeActiveWindow)
                [window makeKeyAndOrderFront: nil];
            else
                [window orderFront: nil];

            if (! recursiveToFrontCall)
            {
                recursiveToFrontCall = true;
                Desktop::getInstance().getMainMouseSource().forceMouseCursorUpdate();
                handleBroughtToFront();
                recursiveToFrontCall = false;
            }
        }
    }

    void toBehind (ComponentPeer* other)
    {
        NSViewComponentPeer* const otherPeer = dynamic_cast <NSViewComponentPeer*> (other);
        jassert (otherPeer != nullptr); // wrong type of window?

        if (otherPeer != nullptr)
        {
            if (isSharedWindow)
            {
                [[view superview] addSubview: view
                                  positioned: NSWindowBelow
                                  relativeTo: otherPeer->view];
            }
            else
            {
                [window orderWindow: NSWindowBelow
                         relativeTo: [otherPeer->window windowNumber]];
            }
        }
    }

    void setIcon (const Image&)
    {
        // to do..
    }

    StringArray getAvailableRenderingEngines()
    {
        StringArray s (ComponentPeer::getAvailableRenderingEngines());

       #if USE_COREGRAPHICS_RENDERING
        s.add ("CoreGraphics Renderer");
       #endif

        return s;
    }

    int getCurrentRenderingEngine() const
    {
        return usingCoreGraphics ? 1 : 0;
    }

    void setCurrentRenderingEngine (int index)
    {
       #if USE_COREGRAPHICS_RENDERING
        if (usingCoreGraphics != (index > 0))
        {
            usingCoreGraphics = index > 0;
            [view setNeedsDisplay: true];
        }
       #endif
    }

    void redirectMouseDown (NSEvent* ev)
    {
        currentModifiers = currentModifiers.withFlags (getModifierForButtonNumber ([ev buttonNumber]));
        sendMouseEvent (ev);
    }

    void redirectMouseUp (NSEvent* ev)
    {
        currentModifiers = currentModifiers.withoutFlags (getModifierForButtonNumber ([ev buttonNumber]));
        sendMouseEvent (ev);
        showArrowCursorIfNeeded();
    }

    void redirectMouseDrag (NSEvent* ev)
    {
        currentModifiers = currentModifiers.withFlags (getModifierForButtonNumber ([ev buttonNumber]));
        sendMouseEvent (ev);
    }

    void redirectMouseMove (NSEvent* ev)
    {
        currentModifiers = currentModifiers.withoutMouseButtons();
        sendMouseEvent (ev);
        showArrowCursorIfNeeded();
    }

    void redirectMouseEnter (NSEvent* ev)
    {
        Desktop::getInstance().getMainMouseSource().forceMouseCursorUpdate();
        currentModifiers = currentModifiers.withoutMouseButtons();
        sendMouseEvent (ev);
    }

    void redirectMouseExit (NSEvent* ev)
    {
        currentModifiers = currentModifiers.withoutMouseButtons();
        sendMouseEvent (ev);
    }

    void redirectMouseWheel (NSEvent* ev)
    {
        updateModifiers (ev);

        MouseWheelDetails wheel;
        wheel.deltaX = 0;
        wheel.deltaY = 0;
        wheel.isReversed = false;
        wheel.isSmooth = false;

       #if ! JUCE_PPC
        @try
        {
           #if defined (MAC_OS_X_VERSION_10_7) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7
            if ([ev respondsToSelector: @selector (isDirectionInvertedFromDevice)])
                wheel.isReversed = [ev isDirectionInvertedFromDevice];

            if ([ev respondsToSelector: @selector (hasPreciseScrollingDeltas)])
            {
                if ([ev hasPreciseScrollingDeltas])
                {
                    const float scale = 0.5f / 256.0f;
                    wheel.deltaX = [ev scrollingDeltaX] * scale;
                    wheel.deltaY = [ev scrollingDeltaY] * scale;
                    wheel.isSmooth = true;
                }
            }
            else
           #endif
            if ([ev respondsToSelector: @selector (deviceDeltaX)])
            {
                const float scale = 0.5f / 256.0f;
                wheel.deltaX = scale * (float) objc_msgSend_fpret (ev, @selector (deviceDeltaX));
                wheel.deltaY = scale * (float) objc_msgSend_fpret (ev, @selector (deviceDeltaY));
            }
        }
        @catch (...)
        {}
       #endif

        if (wheel.deltaX == 0 && wheel.deltaY == 0)
        {
            const float scale = 10.0f / 256.0f;
            wheel.deltaX = [ev deltaX] * scale;
            wheel.deltaY = [ev deltaY] * scale;
        }

        handleMouseWheel (0, getMousePos (ev, view), getMouseTime (ev), wheel);
    }

    void sendMouseEvent (NSEvent* ev)
    {
        updateModifiers (ev);
        handleMouseEvent (0, getMousePos (ev, view), currentModifiers, getMouseTime (ev));
    }

    bool handleKeyEvent (NSEvent* ev, bool isKeyDown)
    {
        String unicode (nsStringToJuce ([ev characters]));
        String unmodified (nsStringToJuce ([ev charactersIgnoringModifiers]));
        int keyCode = getKeyCodeFromEvent (ev);

        //DBG ("unicode: " + unicode + " " + String::toHexString ((int) unicode[0]));
        //DBG ("unmodified: " + unmodified + " " + String::toHexString ((int) unmodified[0]));

        if (unicode.isNotEmpty() || keyCode != 0)
        {
            if (isKeyDown)
            {
                bool used = false;

                while (unicode.length() > 0)
                {
                    juce_wchar textCharacter = unicode[0];
                    unicode = unicode.substring (1);

                    if (([ev modifierFlags] & NSCommandKeyMask) != 0)
                        textCharacter = 0;

                    used = handleKeyUpOrDown (true) || used;
                    used = handleKeyPress (keyCode, textCharacter) || used;
                }

                return used;
            }
            else
            {
                if (handleKeyUpOrDown (false))
                    return true;
            }
        }

        return false;
    }

    bool redirectKeyDown (NSEvent* ev)
    {
        updateKeysDown (ev, true);
        bool used = handleKeyEvent (ev, true);

        if (([ev modifierFlags] & NSCommandKeyMask) != 0)
        {
            // for command keys, the key-up event is thrown away, so simulate one..
            updateKeysDown (ev, false);
            used = (isValidPeer (this) && handleKeyEvent (ev, false)) || used;
        }

        // (If we're running modally, don't allow unused keystrokes to be passed
        // along to other blocked views..)
        if (Component::getCurrentlyModalComponent() != nullptr)
            used = true;

        return used;
    }

    bool redirectKeyUp (NSEvent* ev)
    {
        updateKeysDown (ev, false);
        return handleKeyEvent (ev, false)
                || Component::getCurrentlyModalComponent() != nullptr;
    }

    void redirectModKeyChange (NSEvent* ev)
    {
        keysCurrentlyDown.clear();
        handleKeyUpOrDown (true);

        updateModifiers (ev);
        handleModifierKeysChange();
    }

   #if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
    bool redirectPerformKeyEquivalent (NSEvent* ev)
    {
        if ([ev type] == NSKeyDown)
            return redirectKeyDown (ev);
        else if ([ev type] == NSKeyUp)
            return redirectKeyUp (ev);

        return false;
    }
   #endif

    bool isOpaque()
    {
        return component == nullptr || component->isOpaque();
    }

    void drawRect (NSRect r)
    {
        if (r.size.width < 1.0f || r.size.height < 1.0f)
            return;

        CGContextRef cg = (CGContextRef) [[NSGraphicsContext currentContext] graphicsPort];

        if (! component->isOpaque())
            CGContextClearRect (cg, CGContextGetClipBoundingBox (cg));

       #if USE_COREGRAPHICS_RENDERING
        if (usingCoreGraphics)
        {
            CoreGraphicsContext context (cg, (float) [view frame].size.height);

            insideDrawRect = true;
            handlePaint (context);
            insideDrawRect = false;
        }
        else
       #endif
        {
            const int xOffset = -roundToInt (r.origin.x);
            const int yOffset = -roundToInt ([view frame].size.height - (r.origin.y + r.size.height));
            const int clipW = (int) (r.size.width  + 0.5f);
            const int clipH = (int) (r.size.height + 0.5f);

            RectangleList clip;
            getClipRects (clip, xOffset, yOffset, clipW, clipH);

            if (! clip.isEmpty())
            {
                Image temp (getComponent()->isOpaque() ? Image::RGB : Image::ARGB,
                            clipW, clipH, ! getComponent()->isOpaque());

                {
                    ScopedPointer<LowLevelGraphicsContext> context (component->getLookAndFeel()
                                                                        .createGraphicsContext (temp, Point<int> (xOffset, yOffset), clip));

                    insideDrawRect = true;
                    handlePaint (*context);
                    insideDrawRect = false;
                }

                CGColorSpaceRef colourSpace = CGColorSpaceCreateDeviceRGB();
                CGImageRef image = juce_createCoreGraphicsImage (temp, false, colourSpace, false);
                CGColorSpaceRelease (colourSpace);
                CGContextDrawImage (cg, CGRectMake (r.origin.x, r.origin.y, clipW, clipH), image);
                CGImageRelease (image);
            }
        }
    }

    bool canBecomeKeyWindow()
    {
        return (getStyleFlags() & juce::ComponentPeer::windowIgnoresKeyPresses) == 0;
    }

    void becomeKeyWindow()
    {
        handleBroughtToFront();
        grabFocus();
    }

    bool windowShouldClose()
    {
        if (! isValidPeer (this))
            return YES;

        handleUserClosingWindow();
        return NO;
    }

    void redirectMovedOrResized()
    {
        updateFullscreenStatus();
        handleMovedOrResized();
    }

    void viewMovedToWindow()
    {
        if (isSharedWindow)
            window = [view window];
    }

    NSRect constrainRect (NSRect r)
    {
        if (constrainer != nullptr
            #if defined (MAC_OS_X_VERSION_10_7) && (MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7)
             && ([window styleMask] & NSFullScreenWindowMask) == 0
            #endif
            )
        {
            NSRect current = [window frame];
            current.origin.y = [[[NSScreen screens] objectAtIndex: 0] frame].size.height - current.origin.y - current.size.height;

            r.origin.y = [[[NSScreen screens] objectAtIndex: 0] frame].size.height - r.origin.y - r.size.height;

            Rectangle<int> pos (convertToRectInt (r));
            Rectangle<int> original (convertToRectInt (current));
            const Rectangle<int> screenBounds (Desktop::getInstance().getDisplays().getTotalBounds (true));

           #if defined (MAC_OS_X_VERSION_10_6) && MAC_OS_X_VERSION_MIN_ALLOWED >= MAC_OS_X_VERSION_10_6
            if ([window inLiveResize])
           #else
            if ([window respondsToSelector: @selector (inLiveResize)]
                 && [window performSelector: @selector (inLiveResize)])
           #endif
            {
                constrainer->checkBounds (pos, original, screenBounds,
                                          false, false, true, true);
            }
            else
            {
                constrainer->checkBounds (pos, original, screenBounds,
                                          pos.getY() != original.getY() && pos.getBottom() == original.getBottom(),
                                          pos.getX() != original.getX() && pos.getRight() == original.getRight(),
                                          pos.getY() == original.getY() && pos.getBottom() != original.getBottom(),
                                          pos.getX() == original.getX() && pos.getRight() != original.getRight());
            }

            r.origin.x = pos.getX();
            r.origin.y = [[[NSScreen screens] objectAtIndex: 0] frame].size.height - r.size.height - pos.getY();
            r.size.width = pos.getWidth();
            r.size.height = pos.getHeight();
        }

        return r;
    }

    static void showArrowCursorIfNeeded()
    {
        MouseInputSource& mouse = Desktop::getInstance().getMainMouseSource();

        if (mouse.getComponentUnderMouse() == nullptr
             && Desktop::getInstance().findComponentAt (mouse.getScreenPosition()) == nullptr)
        {
            [[NSCursor arrowCursor] set];
        }
    }

    static void updateModifiers (NSEvent* e)
    {
        updateModifiers ([e modifierFlags]);
    }

    static void updateModifiers (const NSUInteger flags)
    {
        int m = 0;

        if ((flags & NSShiftKeyMask) != 0)        m |= ModifierKeys::shiftModifier;
        if ((flags & NSControlKeyMask) != 0)      m |= ModifierKeys::ctrlModifier;
        if ((flags & NSAlternateKeyMask) != 0)    m |= ModifierKeys::altModifier;
        if ((flags & NSCommandKeyMask) != 0)      m |= ModifierKeys::commandModifier;

        currentModifiers = currentModifiers.withOnlyMouseButtons().withFlags (m);
    }

    static void updateKeysDown (NSEvent* ev, bool isKeyDown)
    {
        updateModifiers (ev);
        int keyCode = getKeyCodeFromEvent (ev);

        if (keyCode != 0)
        {
            if (isKeyDown)
                keysCurrentlyDown.addIfNotAlreadyThere (keyCode);
            else
                keysCurrentlyDown.removeValue (keyCode);
        }
    }

    static int getKeyCodeFromEvent (NSEvent* ev)
    {
        const String unmodified (nsStringToJuce ([ev charactersIgnoringModifiers]));
        int keyCode = unmodified[0];

        if (keyCode == 0x19) // (backwards-tab)
            keyCode = '\t';
        else if (keyCode == 0x03) // (enter)
            keyCode = '\r';
        else
            keyCode = (int) CharacterFunctions::toUpperCase ((juce_wchar) keyCode);

        if (([ev modifierFlags] & NSNumericPadKeyMask) != 0)
        {
            const int numPadConversions[] = { '0', KeyPress::numberPad0, '1', KeyPress::numberPad1,
                                              '2', KeyPress::numberPad2, '3', KeyPress::numberPad3,
                                              '4', KeyPress::numberPad4, '5', KeyPress::numberPad5,
                                              '6', KeyPress::numberPad6, '7', KeyPress::numberPad7,
                                              '8', KeyPress::numberPad8, '9', KeyPress::numberPad9,
                                              '+', KeyPress::numberPadAdd,  '-', KeyPress::numberPadSubtract,
                                              '*', KeyPress::numberPadMultiply, '/', KeyPress::numberPadDivide,
                                              '.', KeyPress::numberPadDecimalPoint, '=', KeyPress::numberPadEquals };

            for (int i = 0; i < numElementsInArray (numPadConversions); i += 2)
                if (keyCode == numPadConversions [i])
                    keyCode = numPadConversions [i + 1];
        }

        return keyCode;
    }

    static int64 getMouseTime (NSEvent* e)
    {
        return (Time::currentTimeMillis() - Time::getMillisecondCounter())
                + (int64) ([e timestamp] * 1000.0);
    }

    static Point<int> getMousePos (NSEvent* e, NSView* view)
    {
        NSPoint p = [view convertPoint: [e locationInWindow] fromView: nil];
        return Point<int> (roundToInt (p.x), roundToInt ([view frame].size.height - p.y));
    }

    static int getModifierForButtonNumber (const NSInteger num)
    {
        return num == 0 ? ModifierKeys::leftButtonModifier
                    : (num == 1 ? ModifierKeys::rightButtonModifier
                                : (num == 2 ? ModifierKeys::middleButtonModifier : 0));
    }

    static unsigned int getNSWindowStyleMask (const int flags) noexcept
    {
        unsigned int style = (flags & windowHasTitleBar) != 0 ? NSTitledWindowMask
                                                              : NSBorderlessWindowMask;

        if ((flags & windowHasMinimiseButton) != 0)  style |= NSMiniaturizableWindowMask;
        if ((flags & windowHasCloseButton) != 0)     style |= NSClosableWindowMask;
        if ((flags & windowIsResizable) != 0)        style |= NSResizableWindowMask;
        return style;
    }

    static NSArray* getSupportedDragTypes()
    {
        return [NSArray arrayWithObjects: NSFilenamesPboardType, NSFilesPromisePboardType, NSStringPboardType, nil];
    }

    BOOL sendDragCallback (const int type, id <NSDraggingInfo> sender)
    {
        NSPasteboard* pasteboard = [sender draggingPasteboard];
        NSString* contentType = [pasteboard availableTypeFromArray: getSupportedDragTypes()];

        if (contentType == nil)
            return false;

        NSPoint p = [view convertPoint: [sender draggingLocation] fromView: nil];
        ComponentPeer::DragInfo dragInfo;
        dragInfo.position.setXY ((int) p.x, (int) ([view frame].size.height - p.y));

        if (contentType == NSStringPboardType)
            dragInfo.text = nsStringToJuce ([pasteboard stringForType: NSStringPboardType]);
        else
            dragInfo.files = getDroppedFiles (pasteboard, contentType);

        if (dragInfo.files.size() > 0 || dragInfo.text.isNotEmpty())
        {
            switch (type)
            {
                case 0:   return handleDragMove (dragInfo);
                case 1:   return handleDragExit (dragInfo);
                case 2:   return handleDragDrop (dragInfo);
                default:  jassertfalse; break;
            }
        }

        return false;
    }

    StringArray getDroppedFiles (NSPasteboard* pasteboard, NSString* contentType)
    {
        StringArray files;
        NSString* iTunesPasteboardType = nsStringLiteral ("CorePasteboardFlavorType 0x6974756E"); // 'itun'

        if (contentType == NSFilesPromisePboardType
             && [[pasteboard types] containsObject: iTunesPasteboardType])
        {
            id list = [pasteboard propertyListForType: iTunesPasteboardType];

            if ([list isKindOfClass: [NSDictionary class]])
            {
                NSDictionary* iTunesDictionary = (NSDictionary*) list;
                NSArray* tracks = [iTunesDictionary valueForKey: nsStringLiteral ("Tracks")];
                NSEnumerator* enumerator = [tracks objectEnumerator];
                NSDictionary* track;

                while ((track = [enumerator nextObject]) != nil)
                {
                    NSURL* url = [NSURL URLWithString: [track valueForKey: nsStringLiteral ("Location")]];

                    if ([url isFileURL])
                        files.add (nsStringToJuce ([url path]));
                }
            }
        }
        else
        {
            id list = [pasteboard propertyListForType: NSFilenamesPboardType];

            if ([list isKindOfClass: [NSArray class]])
            {
                NSArray* items = (NSArray*) [pasteboard propertyListForType: NSFilenamesPboardType];

                for (unsigned int i = 0; i < [items count]; ++i)
                    files.add (nsStringToJuce ((NSString*) [items objectAtIndex: i]));
            }
        }

        return files;
    }

    //==============================================================================
    void viewFocusGain()
    {
        if (currentlyFocusedPeer != this)
        {
            if (ComponentPeer::isValidPeer (currentlyFocusedPeer))
                currentlyFocusedPeer->handleFocusLoss();

            currentlyFocusedPeer = this;
            handleFocusGain();
        }
    }

    void viewFocusLoss()
    {
        if (currentlyFocusedPeer == this)
        {
            currentlyFocusedPeer = nullptr;
            handleFocusLoss();
        }
    }

    bool isFocused() const
    {
        return isSharedWindow ? this == currentlyFocusedPeer
                              : [window isKeyWindow];
    }

    void grabFocus()
    {
        if (window != nil)
        {
            [window makeKeyWindow];
            [window makeFirstResponder: view];

            viewFocusGain();
        }
    }

    void textInputRequired (const Point<int>&) {}

    //==============================================================================
    void repaint (const Rectangle<int>& area)
    {
        if (insideDrawRect)
        {
            class AsyncRepaintMessage  : public CallbackMessage
            {
            public:
                AsyncRepaintMessage (NSViewComponentPeer* const peer_, const Rectangle<int>& rect_)
                    : peer (peer_), rect (rect_)
                {}

                void messageCallback()
                {
                    if (ComponentPeer::isValidPeer (peer))
                        peer->repaint (rect);
                }

            private:
                NSViewComponentPeer* const peer;
                const Rectangle<int> rect;
            };

            (new AsyncRepaintMessage (this, area))->post();
        }
        else
        {
            [view setNeedsDisplayInRect: NSMakeRect ((CGFloat) area.getX(), [view frame].size.height - (CGFloat) area.getBottom(),
                                                     (CGFloat) area.getWidth(), (CGFloat) area.getHeight())];
        }
    }

    void performAnyPendingRepaintsNow()
    {
        [view displayIfNeeded];
    }

    //==============================================================================
    NSWindow* window;
    NSView* view;
    bool isSharedWindow, fullScreen, insideDrawRect;
    bool usingCoreGraphics, recursiveToFrontCall, isZooming, textWasInserted;
    String stringBeingComposed;
    NSNotificationCenter* notificationCenter;

    static ModifierKeys currentModifiers;
    static ComponentPeer* currentlyFocusedPeer;
    static Array<int> keysCurrentlyDown;

private:
    static NSView* createViewInstance();
    static NSWindow* createWindowInstance();

    static void setOwner (id viewOrWindow, NSViewComponentPeer* newOwner)
    {
        object_setInstanceVariable (viewOrWindow, "owner", newOwner);
    }

    void getClipRects (RectangleList& clip, const int xOffset, const int yOffset, const int clipW, const int clipH)
    {
        const NSRect* rects = nullptr;
        NSInteger numRects = 0;
        [view getRectsBeingDrawn: &rects count: &numRects];

        const Rectangle<int> clipBounds (clipW, clipH);
        const CGFloat viewH = [view frame].size.height;

        for (int i = 0; i < numRects; ++i)
            clip.addWithoutMerging (clipBounds.getIntersection (Rectangle<int> (roundToInt (rects[i].origin.x) + xOffset,
                                                                                roundToInt (viewH - (rects[i].origin.y + rects[i].size.height)) + yOffset,
                                                                                roundToInt (rects[i].size.width),
                                                                                roundToInt (rects[i].size.height))));
    }

    static void appFocusChanged()
    {
        keysCurrentlyDown.clear();

        if (isValidPeer (currentlyFocusedPeer))
        {
            if (Process::isForegroundProcess())
            {
                currentlyFocusedPeer->handleFocusGain();
                ModalComponentManager::getInstance()->bringModalComponentsToFront();
            }
            else
            {
                currentlyFocusedPeer->handleFocusLoss();
            }
        }
    }

    static bool checkEventBlockedByModalComps (NSEvent* e)
    {
        if (Component::getNumCurrentlyModalComponents() == 0)
            return false;

        NSWindow* const w = [e window];
        if (w == nil || [w worksWhenModal])
            return false;

        bool isKey = false, isInputAttempt = false;

        switch ([e type])
        {
            case NSKeyDown:
            case NSKeyUp:
                isKey = isInputAttempt = true;
                break;

            case NSLeftMouseDown:
            case NSRightMouseDown:
            case NSOtherMouseDown:
                isInputAttempt = true;
                break;

            case NSLeftMouseDragged:
            case NSRightMouseDragged:
            case NSLeftMouseUp:
            case NSRightMouseUp:
            case NSOtherMouseUp:
            case NSOtherMouseDragged:
                if (Desktop::getInstance().getDraggingMouseSource(0) != nullptr)
                    return false;
                break;

            case NSMouseMoved:
            case NSMouseEntered:
            case NSMouseExited:
            case NSCursorUpdate:
            case NSScrollWheel:
            case NSTabletPoint:
            case NSTabletProximity:
                break;

            default:
                return false;
        }

        for (int i = ComponentPeer::getNumPeers(); --i >= 0;)
        {
            ComponentPeer* const peer = ComponentPeer::getPeer (i);
            NSView* const compView = (NSView*) peer->getNativeHandle();

            if ([compView window] == w)
            {
                if (isKey)
                {
                    if (compView == [w firstResponder])
                        return false;
                }
                else
                {
                    NSViewComponentPeer* nsViewPeer = dynamic_cast<NSViewComponentPeer*> (peer);

                    if ((nsViewPeer == nullptr || ! nsViewPeer->isSharedWindow)
                            ? NSPointInRect ([e locationInWindow], NSMakeRect (0, 0, [w frame].size.width, [w frame].size.height))
                            : NSPointInRect ([compView convertPoint: [e locationInWindow] fromView: nil], [compView bounds]))
                        return false;
                }
            }
        }

        if (isInputAttempt)
        {
            if (! [NSApp isActive])
                [NSApp activateIgnoringOtherApps: YES];

            Component* const modal = Component::getCurrentlyModalComponent (0);
            if (modal != nullptr)
                modal->inputAttemptWhenModal();
        }

        return true;
    }

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (NSViewComponentPeer);
};

//==============================================================================
struct JuceNSViewClass   : public ObjCClass <NSView>
{
    JuceNSViewClass()  : ObjCClass <NSView> ("JUCEView_")
    {
        addIvar<NSViewComponentPeer*> ("owner");

        addMethod (@selector (isOpaque),                      isOpaque,                   "c@:");
        addMethod (@selector (drawRect:),                     drawRect,                   "v@:", @encode (NSRect));
        addMethod (@selector (mouseDown:),                    mouseDown,                  "v@:@");
        addMethod (@selector (asyncMouseDown:),               asyncMouseDown,             "v@:@");
        addMethod (@selector (mouseUp:),                      mouseUp,                    "v@:@");
        addMethod (@selector (asyncMouseUp:),                 asyncMouseUp,               "v@:@");
        addMethod (@selector (mouseDragged:),                 mouseDragged,               "v@:@");
        addMethod (@selector (mouseMoved:),                   mouseMoved,                 "v@:@");
        addMethod (@selector (mouseEntered:),                 mouseEntered,               "v@:@");
        addMethod (@selector (mouseExited:),                  mouseExited,                "v@:@");
        addMethod (@selector (rightMouseDown:),               rightMouseDown,             "v@:@");
        addMethod (@selector (rightMouseDragged:),            rightMouseDragged,          "v@:@");
        addMethod (@selector (rightMouseUp:),                 rightMouseUp,               "v@:@");
        addMethod (@selector (otherMouseDown:),               otherMouseDown,             "v@:@");
        addMethod (@selector (otherMouseDragged:),            otherMouseDragged,          "v@:@");
        addMethod (@selector (otherMouseUp:),                 otherMouseUp,               "v@:@");
        addMethod (@selector (scrollWheel:),                  scrollWheel,                "v@:@");
        addMethod (@selector (acceptsFirstMouse:),            acceptsFirstMouse,          "v@:@");
        addMethod (@selector (frameChanged:),                 frameChanged,               "v@:@");
        addMethod (@selector (viewDidMoveToWindow),           viewDidMoveToWindow,        "v@:");
        addMethod (@selector (keyDown:),                      keyDown,                    "v@:@");
        addMethod (@selector (keyUp:),                        keyUp,                      "v@:@");
        addMethod (@selector (insertText:),                   insertText,                 "v@:@");
        addMethod (@selector (doCommandBySelector:),          doCommandBySelector,        "v@::");
        addMethod (@selector (setMarkedText:selectedRange:),  setMarkedText,              "v@:@", @encode (NSRange));
        addMethod (@selector (unmarkText),                    unmarkText,                 "v@:");
        addMethod (@selector (hasMarkedText),                 hasMarkedText,              "c@:");
        addMethod (@selector (conversationIdentifier),        conversationIdentifier,     "l@:");
        addMethod (@selector (attributedSubstringFromRange:), attributedSubstringFromRange, "@@:", @encode (NSRange));
        addMethod (@selector (markedRange),                   markedRange,                @encode (NSRange), "@:");
        addMethod (@selector (selectedRange),                 selectedRange,              @encode (NSRange), "@:");
        addMethod (@selector (firstRectForCharacterRange:),   firstRectForCharacterRange, @encode (NSRect), "@:", @encode (NSRange));
        addMethod (@selector (validAttributesForMarkedText),  validAttributesForMarkedText, "@@:");
        addMethod (@selector (flagsChanged:),                 flagsChanged,               "v@:@");

        addMethod (@selector (becomeFirstResponder),          becomeFirstResponder,       "c@:");
        addMethod (@selector (resignFirstResponder),          resignFirstResponder,       "c@:");
        addMethod (@selector (acceptsFirstResponder),         acceptsFirstResponder,      "c@:");

       #if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
        addMethod (@selector (performKeyEquivalent:),         performKeyEquivalent,       "c@:@");
       #endif

        addMethod (@selector (draggingEntered:),              draggingEntered,            @encode (NSDragOperation), "@:@");
        addMethod (@selector (draggingUpdated:),              draggingUpdated,            @encode (NSDragOperation), "@:@");
        addMethod (@selector (draggingEnded:),                draggingEnded,              "v@:@");
        addMethod (@selector (draggingExited:),               draggingExited,             "v@:@");
        addMethod (@selector (prepareForDragOperation:),      prepareForDragOperation,    "c@:@");
        addMethod (@selector (performDragOperation:),         performDragOperation,       "c@:@");
        addMethod (@selector (concludeDragOperation:),        concludeDragOperation,      "v@:@");

        addProtocol (@protocol (NSTextInput));

        registerClass();
    }

private:
    static NSViewComponentPeer* getOwner (id self)
    {
        return getIvar<NSViewComponentPeer*> (self, "owner");
    }

    //==============================================================================
    static void drawRect (id self, SEL, NSRect r)
    {
        NSViewComponentPeer* const owner = getOwner (self);

        if (owner != nullptr)
            owner->drawRect (r);
    }

    static BOOL isOpaque (id self, SEL)
    {
        NSViewComponentPeer* const owner = getOwner (self);
        return owner == nullptr || owner->isOpaque();
    }

    //==============================================================================
    static void mouseDown (id self, SEL, NSEvent* ev)
    {
        if (JUCEApplication::isStandaloneApp())
            [self performSelector: @selector (asyncMouseDown:)
                       withObject: ev];
        else
            // In some host situations, the host will stop modal loops from working
            // correctly if they're called from a mouse event, so we'll trigger
            // the event asynchronously..
            [self performSelectorOnMainThread: @selector (asyncMouseDown:)
                                   withObject: ev
                                waitUntilDone: NO];
    }

    static void asyncMouseDown (id self, SEL, NSEvent* ev)
    {
        NSViewComponentPeer* const owner = getOwner (self);

        if (owner != nullptr)
            owner->redirectMouseDown (ev);
    }

    static void mouseUp (id self, SEL, NSEvent* ev)
    {
        if (! JUCEApplication::isStandaloneApp())
            [self performSelector: @selector (asyncMouseUp:)
                       withObject: ev];
        else
            // In some host situations, the host will stop modal loops from working
            // correctly if they're called from a mouse event, so we'll trigger
            // the event asynchronously..
            [self performSelectorOnMainThread: @selector (asyncMouseUp:)
                                   withObject: ev
                                waitUntilDone: NO];
    }

    static void asyncMouseUp (id self, SEL, NSEvent* ev)    { NSViewComponentPeer* const owner = getOwner (self); if (owner != nullptr) owner->redirectMouseUp    (ev); }
    static void mouseDragged (id self, SEL, NSEvent* ev)    { NSViewComponentPeer* const owner = getOwner (self); if (owner != nullptr) owner->redirectMouseDrag  (ev); }
    static void mouseMoved   (id self, SEL, NSEvent* ev)    { NSViewComponentPeer* const owner = getOwner (self); if (owner != nullptr) owner->redirectMouseMove  (ev); }
    static void mouseEntered (id self, SEL, NSEvent* ev)    { NSViewComponentPeer* const owner = getOwner (self); if (owner != nullptr) owner->redirectMouseEnter (ev); }
    static void mouseExited  (id self, SEL, NSEvent* ev)    { NSViewComponentPeer* const owner = getOwner (self); if (owner != nullptr) owner->redirectMouseExit  (ev); }
    static void scrollWheel  (id self, SEL, NSEvent* ev)    { NSViewComponentPeer* const owner = getOwner (self); if (owner != nullptr) owner->redirectMouseWheel (ev); }

    static void rightMouseDown    (id self, SEL, NSEvent* ev)   { [(NSView*) self mouseDown:    ev]; }
    static void rightMouseDragged (id self, SEL, NSEvent* ev)   { [(NSView*) self mouseDragged: ev]; }
    static void rightMouseUp      (id self, SEL, NSEvent* ev)   { [(NSView*) self mouseUp:      ev]; }
    static void otherMouseDown    (id self, SEL, NSEvent* ev)   { [(NSView*) self mouseDown:    ev]; }
    static void otherMouseDragged (id self, SEL, NSEvent* ev)   { [(NSView*) self mouseDragged: ev]; }
    static void otherMouseUp      (id self, SEL, NSEvent* ev)   { [(NSView*) self mouseUp:      ev]; }

    static BOOL acceptsFirstMouse (id, SEL, NSEvent*)       { return YES; }

    static void frameChanged (id self, SEL, NSNotification*)
    {
        NSViewComponentPeer* const owner = getOwner (self);

        if (owner != nullptr)
            owner->redirectMovedOrResized();
    }

    static void viewDidMoveToWindow (id self, SEL)
    {
        NSViewComponentPeer* const owner = getOwner (self);

        if (owner != nullptr)
            owner->viewMovedToWindow();
    }

    //==============================================================================
    static void keyDown (id self, SEL, NSEvent* ev)
    {
        NSViewComponentPeer* const owner = getOwner (self);

        TextInputTarget* const target = owner->findCurrentTextInputTarget();
        owner->textWasInserted = false;

        if (target != nullptr)
            [(NSView*) self interpretKeyEvents: [NSArray arrayWithObject: ev]];
        else
            owner->stringBeingComposed = String::empty;

        if ((! owner->textWasInserted) && (owner == nullptr || ! owner->redirectKeyDown (ev)))
        {
            objc_super s = { self, [NSView class] };
            objc_msgSendSuper (&s, @selector (keyDown:), ev);
        }
    }

    static void keyUp (id self, SEL, NSEvent* ev)
    {
        NSViewComponentPeer* const owner = getOwner (self);

        if (owner == nullptr || ! owner->redirectKeyUp (ev))
        {
            objc_super s = { self, [NSView class] };
            objc_msgSendSuper (&s, @selector (keyUp:), ev);
        }
    }

    //==============================================================================
    static void insertText (id self, SEL, id aString)
    {
        // This commits multi-byte text when return is pressed, or after every keypress for western keyboards
        NSViewComponentPeer* const owner = getOwner (self);

        NSString* newText = [aString isKindOfClass: [NSAttributedString class]] ? [aString string] : aString;

        if ([newText length] > 0)
        {
            TextInputTarget* const target = owner->findCurrentTextInputTarget();

            if (target != nullptr)
            {
                target->insertTextAtCaret (nsStringToJuce (newText));
                owner->textWasInserted = true;
            }
        }

        owner->stringBeingComposed = String::empty;
    }

    static void doCommandBySelector (id, SEL, SEL) {}

    static void setMarkedText (id self, SEL, id aString, NSRange)
    {
        NSViewComponentPeer* const owner = getOwner (self);

        owner->stringBeingComposed = nsStringToJuce ([aString isKindOfClass: [NSAttributedString class]]
                                                       ? [aString string] : aString);

        TextInputTarget* const target = owner->findCurrentTextInputTarget();

        if (target != nullptr)
        {
            const Range<int> currentHighlight (target->getHighlightedRegion());
            target->insertTextAtCaret (owner->stringBeingComposed);
            target->setHighlightedRegion (currentHighlight.withLength (owner->stringBeingComposed.length()));
            owner->textWasInserted = true;
        }
    }

    static void unmarkText (id self, SEL)
    {
        NSViewComponentPeer* const owner = getOwner (self);

        if (owner->stringBeingComposed.isNotEmpty())
        {
            TextInputTarget* const target = owner->findCurrentTextInputTarget();

            if (target != nullptr)
            {
                target->insertTextAtCaret (owner->stringBeingComposed);
                owner->textWasInserted = true;
            }

            owner->stringBeingComposed = String::empty;
        }
    }

    static BOOL hasMarkedText (id self, SEL)
    {
        return getOwner (self)->stringBeingComposed.isNotEmpty();
    }

    static long conversationIdentifier (id self, SEL)
    {
        return (long) (pointer_sized_int) self;
    }

    static NSAttributedString* attributedSubstringFromRange (id self, SEL, NSRange theRange)
    {
        NSViewComponentPeer* const owner = getOwner (self);
        TextInputTarget* const target = owner->findCurrentTextInputTarget();

        if (target != nullptr)
        {
            const Range<int> r ((int) theRange.location,
                                (int) (theRange.location + theRange.length));

            return [[[NSAttributedString alloc] initWithString: juceStringToNS (target->getTextInRange (r))] autorelease];
        }

        return nil;
    }

    static NSRange markedRange (id self, SEL)
    {
        NSViewComponentPeer* const owner = getOwner (self);
        return owner->stringBeingComposed.isNotEmpty() ? NSMakeRange (0, owner->stringBeingComposed.length())
                                                       : NSMakeRange (NSNotFound, 0);
    }

    static NSRange selectedRange (id self, SEL)
    {
        NSViewComponentPeer* const owner = getOwner (self);
        TextInputTarget* const target = owner->findCurrentTextInputTarget();

        if (target != nullptr)
        {
            const Range<int> highlight (target->getHighlightedRegion());

            if (! highlight.isEmpty())
                return NSMakeRange (highlight.getStart(), highlight.getLength());
        }

        return NSMakeRange (NSNotFound, 0);
    }

    static NSRect firstRectForCharacterRange (id self, SEL, NSRange)
    {
        NSViewComponentPeer* const owner = getOwner (self);
        Component* const comp = dynamic_cast <Component*> (owner->findCurrentTextInputTarget());

        if (comp == nullptr)
            return NSMakeRect (0, 0, 0, 0);

        const Rectangle<int> bounds (comp->getScreenBounds());

        return NSMakeRect (bounds.getX(),
                           [[[NSScreen screens] objectAtIndex: 0] frame].size.height - bounds.getY(),
                           bounds.getWidth(),
                           bounds.getHeight());
    }

    static NSUInteger characterIndexForPoint (id, SEL, NSPoint)     { return NSNotFound; }
    static NSArray* validAttributesForMarkedText (id, SEL)          { return [NSArray array]; }

    //==============================================================================
    static void flagsChanged (id self, SEL, NSEvent* ev)
    {
        NSViewComponentPeer* const owner = getOwner (self);

        if (owner != nullptr)
            owner->redirectModKeyChange (ev);
    }

    #if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
    static BOOL performKeyEquivalent (id self, SEL, NSEvent* ev)
    {
        NSViewComponentPeer* const owner = getOwner (self);

        if (owner != nullptr && owner->redirectPerformKeyEquivalent (ev))
            return true;

        objc_super s = { self, [NSView class] };
        return objc_msgSendSuper (&s, @selector (performKeyEquivalent:), ev) != nil;
    }
    #endif

    static BOOL becomeFirstResponder (id self, SEL)
    {
        NSViewComponentPeer* const owner = getOwner (self);
        if (owner != nullptr)
            owner->viewFocusGain();

        return YES;
    }

    static BOOL resignFirstResponder (id self, SEL)
    {
        NSViewComponentPeer* const owner = getOwner (self);
        if (owner != nullptr)
            owner->viewFocusLoss();

        return YES;
    }

    static BOOL acceptsFirstResponder (id self, SEL)
    {
        NSViewComponentPeer* const owner = getOwner (self);
        return owner != nullptr && owner->canBecomeKeyWindow();
    }

    //==============================================================================
    static NSDragOperation draggingEntered (id self, SEL, id <NSDraggingInfo> sender)
    {
        NSViewComponentPeer* const owner = getOwner (self);

        if (owner != nullptr && owner->sendDragCallback (0, sender))
            return NSDragOperationCopy | NSDragOperationMove | NSDragOperationGeneric;
        else
            return NSDragOperationNone;
    }

    static NSDragOperation draggingUpdated (id self, SEL, id <NSDraggingInfo> sender)
    {
        NSViewComponentPeer* const owner = getOwner (self);

        if (owner != nullptr && owner->sendDragCallback (0, sender))
            return NSDragOperationCopy | NSDragOperationMove | NSDragOperationGeneric;
        else
            return NSDragOperationNone;
    }

    static void draggingEnded (id self, SEL, id <NSDraggingInfo> sender)
    {
        NSViewComponentPeer* const owner = getOwner (self);

        if (owner != nullptr)
            owner->sendDragCallback (1, sender);
    }

    static void draggingExited (id self, SEL, id <NSDraggingInfo> sender)
    {
        NSViewComponentPeer* const owner = getOwner (self);

        if (owner != nullptr)
            owner->sendDragCallback (1, sender);
    }

    static BOOL prepareForDragOperation (id self, SEL, id <NSDraggingInfo>)
    {
        return YES;
    }

    static BOOL performDragOperation (id self, SEL, id <NSDraggingInfo> sender)
    {
        NSViewComponentPeer* const owner = getOwner (self);
        return owner != nullptr && owner->sendDragCallback (2, sender);
    }

    static void concludeDragOperation (id, SEL, id <NSDraggingInfo>) {}
};

//==============================================================================
struct JuceNSWindowClass   : public ObjCClass <NSWindow>
{
    JuceNSWindowClass()  : ObjCClass <NSWindow> ("JUCEWindow_")
    {
        addIvar<NSViewComponentPeer*> ("owner");

        addMethod (@selector (canBecomeKeyWindow),            canBecomeKeyWindow,         "c@:");
        addMethod (@selector (becomeKeyWindow),               becomeKeyWindow,            "v@:");
        addMethod (@selector (windowShouldClose:),            windowShouldClose,          "c@:@");
        addMethod (@selector (constrainFrameRect:toScreen:),  constrainFrameRect,         @encode (NSRect), "@:", @encode (NSRect*), "@");
        addMethod (@selector (windowWillResize:toSize:),      windowWillResize,           @encode (NSSize), "@:@", @encode (NSSize));
        addMethod (@selector (zoom),                          zoom,                       "v@:@");
        addMethod (@selector (windowWillMove),                windowWillMove,             "v@:@");

       #if defined (MAC_OS_X_VERSION_10_6) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_6
        addProtocol (@protocol (NSWindowDelegate));
       #endif

        registerClass();
    }

private:
    static NSViewComponentPeer* getOwner (id self)
    {
        return getIvar<NSViewComponentPeer*> (self, "owner");
    }

    //==============================================================================
    static BOOL canBecomeKeyWindow (id self, SEL)
    {
        NSViewComponentPeer* const owner = getOwner (self);
        return owner != nullptr && owner->canBecomeKeyWindow();
    }

    static void becomeKeyWindow (id self, SEL)
    {
        sendSuperclassMessage (self, @selector (becomeKeyWindow));

        NSViewComponentPeer* const owner = getOwner (self);

        if (owner != nullptr)
            owner->becomeKeyWindow();
    }

    static BOOL windowShouldClose (id self, SEL, id /*window*/)
    {
        NSViewComponentPeer* const owner = getOwner (self);
        return owner == nullptr || owner->windowShouldClose();
    }

    static NSRect constrainFrameRect (id self, SEL, NSRect frameRect, NSScreen*)
    {
        NSViewComponentPeer* const owner = getOwner (self);

        if (owner != nullptr)
            frameRect = owner->constrainRect (frameRect);

        return frameRect;
    }

    static NSSize windowWillResize (id self, SEL, NSWindow*, NSSize proposedFrameSize)
    {
        NSViewComponentPeer* const owner = getOwner (self);

        if (owner->isZooming)
            return proposedFrameSize;

        NSRect frameRect = [(NSWindow*) self frame];
        frameRect.origin.y -= proposedFrameSize.height - frameRect.size.height;
        frameRect.size = proposedFrameSize;

        if (owner != nullptr)
            frameRect = owner->constrainRect (frameRect);

        if (juce::Component::getCurrentlyModalComponent() != nullptr
              && owner->getComponent()->isCurrentlyBlockedByAnotherModalComponent()
              && owner->hasNativeTitleBar())
            juce::Component::getCurrentlyModalComponent()->inputAttemptWhenModal();

        return frameRect.size;
    }

    static void zoom (id self, SEL, id sender)
    {
        NSViewComponentPeer* const owner = getOwner (self);

        owner->isZooming = true;
        objc_super s = { self, [NSWindow class] };
        objc_msgSendSuper (&s, @selector(zoom), sender);
        owner->isZooming = false;

        owner->redirectMovedOrResized();
    }

    static void windowWillMove (id self, SEL, NSNotification*)
    {
        NSViewComponentPeer* const owner = getOwner (self);

        if (juce::Component::getCurrentlyModalComponent() != nullptr
              && owner->getComponent()->isCurrentlyBlockedByAnotherModalComponent()
              && owner->hasNativeTitleBar())
            juce::Component::getCurrentlyModalComponent()->inputAttemptWhenModal();
    }
};

NSView* NSViewComponentPeer::createViewInstance()
{
    static JuceNSViewClass cls;
    return cls.createInstance();
}

NSWindow* NSViewComponentPeer::createWindowInstance()
{
    static JuceNSWindowClass cls;
    return cls.createInstance();
}


//==============================================================================
ModifierKeys NSViewComponentPeer::currentModifiers;
ComponentPeer* NSViewComponentPeer::currentlyFocusedPeer = nullptr;
Array<int> NSViewComponentPeer::keysCurrentlyDown;

//==============================================================================
bool KeyPress::isKeyCurrentlyDown (const int keyCode)
{
    if (NSViewComponentPeer::keysCurrentlyDown.contains (keyCode))
        return true;

    if (keyCode >= 'A' && keyCode <= 'Z'
         && NSViewComponentPeer::keysCurrentlyDown.contains ((int) CharacterFunctions::toLowerCase ((juce_wchar) keyCode)))
        return true;

    if (keyCode >= 'a' && keyCode <= 'z'
         && NSViewComponentPeer::keysCurrentlyDown.contains ((int) CharacterFunctions::toUpperCase ((juce_wchar) keyCode)))
        return true;

    return false;
}


ModifierKeys ModifierKeys::getCurrentModifiersRealtime() noexcept
{
    if ([NSEvent respondsToSelector: @selector (modifierFlags)])
        NSViewComponentPeer::updateModifiers ((NSUInteger) [NSEvent modifierFlags]);

    return NSViewComponentPeer::currentModifiers;
}

void ModifierKeys::updateCurrentModifiers() noexcept
{
    currentModifiers = NSViewComponentPeer::currentModifiers;
}


//==============================================================================
void Desktop::createMouseInputSources()
{
    mouseSources.add (new MouseInputSource (0, true));
}

//==============================================================================
void Desktop::setKioskComponent (Component* kioskModeComponent, bool enableOrDisable, bool allowMenusAndBars)
{
   #if defined (MAC_OS_X_VERSION_10_6) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_6

    NSViewComponentPeer* const peer = dynamic_cast<NSViewComponentPeer*> (kioskModeComponent->getPeer());

   #if defined (MAC_OS_X_VERSION_10_7) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7
    if (peer != nullptr
         && peer->hasNativeTitleBar()
         && [peer->window respondsToSelector: @selector (toggleFullScreen:)])
    {
        [peer->window performSelector: @selector (toggleFullScreen:)
                           withObject: [NSNumber numberWithBool: (BOOL) enableOrDisable]];
    }
    else
   #endif
    {
        if (enableOrDisable)
        {
            if (peer->hasNativeTitleBar())
                [peer->window setStyleMask: NSBorderlessWindowMask];

            [NSApp setPresentationOptions: (allowMenusAndBars ? (NSApplicationPresentationAutoHideDock | NSApplicationPresentationAutoHideMenuBar)
                                                              : (NSApplicationPresentationHideDock | NSApplicationPresentationHideMenuBar))];
            kioskModeComponent->setBounds (Desktop::getInstance().getDisplays().getMainDisplay().totalArea);
            peer->becomeKeyWindow();
        }
        else
        {
            if (peer->hasNativeTitleBar())
            {
                [peer->window setStyleMask: (NSViewComponentPeer::getNSWindowStyleMask (peer->getStyleFlags()))];
                peer->setTitle (peer->component->getName()); // required to force the OS to update the title
            }

            [NSApp setPresentationOptions: NSApplicationPresentationDefault];
        }
    }
   #elif JUCE_SUPPORT_CARBON
    if (enableOrDisable)
    {
        SetSystemUIMode (kUIModeAllSuppressed, allowMenusAndBars ? kUIOptionAutoShowMenuBar : 0);
        kioskModeComponent->setBounds (Desktop::getInstance().getDisplays().getMainDisplay().totalArea);
    }
    else
    {
        SetSystemUIMode (kUIModeNormal, 0);
    }
   #else
    // If you're targeting OSes earlier than 10.6 and want to use this feature,
    // you'll need to enable JUCE_SUPPORT_CARBON.
    jassertfalse;
   #endif
}

//==============================================================================
ComponentPeer* Component::createNewPeer (int styleFlags, void* windowToAttachTo)
{
    return new NSViewComponentPeer (this, styleFlags, (NSView*) windowToAttachTo);
}

//==============================================================================
const int KeyPress::spaceKey        = ' ';
const int KeyPress::returnKey       = 0x0d;
const int KeyPress::escapeKey       = 0x1b;
const int KeyPress::backspaceKey    = 0x7f;
const int KeyPress::leftKey         = NSLeftArrowFunctionKey;
const int KeyPress::rightKey        = NSRightArrowFunctionKey;
const int KeyPress::upKey           = NSUpArrowFunctionKey;
const int KeyPress::downKey         = NSDownArrowFunctionKey;
const int KeyPress::pageUpKey       = NSPageUpFunctionKey;
const int KeyPress::pageDownKey     = NSPageDownFunctionKey;
const int KeyPress::endKey          = NSEndFunctionKey;
const int KeyPress::homeKey         = NSHomeFunctionKey;
const int KeyPress::deleteKey       = NSDeleteFunctionKey;
const int KeyPress::insertKey       = -1;
const int KeyPress::tabKey          = 9;
const int KeyPress::F1Key           = NSF1FunctionKey;
const int KeyPress::F2Key           = NSF2FunctionKey;
const int KeyPress::F3Key           = NSF3FunctionKey;
const int KeyPress::F4Key           = NSF4FunctionKey;
const int KeyPress::F5Key           = NSF5FunctionKey;
const int KeyPress::F6Key           = NSF6FunctionKey;
const int KeyPress::F7Key           = NSF7FunctionKey;
const int KeyPress::F8Key           = NSF8FunctionKey;
const int KeyPress::F9Key           = NSF9FunctionKey;
const int KeyPress::F10Key          = NSF10FunctionKey;
const int KeyPress::F11Key          = NSF1FunctionKey;
const int KeyPress::F12Key          = NSF12FunctionKey;
const int KeyPress::F13Key          = NSF13FunctionKey;
const int KeyPress::F14Key          = NSF14FunctionKey;
const int KeyPress::F15Key          = NSF15FunctionKey;
const int KeyPress::F16Key          = NSF16FunctionKey;
const int KeyPress::numberPad0      = 0x30020;
const int KeyPress::numberPad1      = 0x30021;
const int KeyPress::numberPad2      = 0x30022;
const int KeyPress::numberPad3      = 0x30023;
const int KeyPress::numberPad4      = 0x30024;
const int KeyPress::numberPad5      = 0x30025;
const int KeyPress::numberPad6      = 0x30026;
const int KeyPress::numberPad7      = 0x30027;
const int KeyPress::numberPad8      = 0x30028;
const int KeyPress::numberPad9      = 0x30029;
const int KeyPress::numberPadAdd            = 0x3002a;
const int KeyPress::numberPadSubtract       = 0x3002b;
const int KeyPress::numberPadMultiply       = 0x3002c;
const int KeyPress::numberPadDivide         = 0x3002d;
const int KeyPress::numberPadSeparator      = 0x3002e;
const int KeyPress::numberPadDecimalPoint   = 0x3002f;
const int KeyPress::numberPadEquals         = 0x30030;
const int KeyPress::numberPadDelete         = 0x30031;
const int KeyPress::playKey         = 0x30000;
const int KeyPress::stopKey         = 0x30001;
const int KeyPress::fastForwardKey  = 0x30002;
const int KeyPress::rewindKey       = 0x30003;
