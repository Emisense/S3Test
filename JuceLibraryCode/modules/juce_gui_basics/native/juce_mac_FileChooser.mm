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

#if JUCE_MAC

struct FileChooserDelegateClass  : public ObjCClass <NSObject>
{
    FileChooserDelegateClass()  : ObjCClass <NSObject> ("JUCEFileChooser_")
    {
        addIvar<StringArray*> ("filters");

        addMethod (@selector (dealloc),                   dealloc,            "v@:");
        addMethod (@selector (panel:shouldShowFilename:), shouldShowFilename, "c@:@@");

       #if defined (MAC_OS_X_VERSION_10_6) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_6
        addProtocol (@protocol (NSOpenSavePanelDelegate));
       #endif

        registerClass();
    }

    static void setFilters (id self, StringArray* filters)
    {
        object_setInstanceVariable (self, "filters", filters);
    }

private:
    static void dealloc (id self, SEL)
    {
        delete getIvar<StringArray*> (self, "filters");
        sendSuperclassMessage (self, @selector (dealloc));
    }

    static BOOL shouldShowFilename (id self, SEL, id /*sender*/, NSString* filename)
    {
        StringArray* const filters = getIvar<StringArray*> (self, "filters");

        const File f (nsStringToJuce (filename));

        for (int i = filters->size(); --i >= 0;)
            if (f.getFileName().matchesWildcard ((*filters)[i], true))
                return true;

       #if (! defined (MAC_OS_X_VERSION_10_7)) || MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_7
        NSError* error;
        NSString* name = [[NSWorkspace sharedWorkspace] typeOfFile: filename error: &error];

        if ([name isEqualToString: nsStringLiteral ("com.apple.alias-file")])
        {
            FSRef ref;
            FSPathMakeRef ((const UInt8*) [filename fileSystemRepresentation], &ref, nullptr);

            Boolean targetIsFolder = false, wasAliased = false;
            FSResolveAliasFileWithMountFlags (&ref, true, &targetIsFolder, &wasAliased, 0);

            return wasAliased && targetIsFolder;
        }
       #endif

        return f.isDirectory()
                 && ! [[NSWorkspace sharedWorkspace] isFilePackageAtPath: filename];
    }
};

//==============================================================================
class TemporaryMainMenuWithStandardCommands
{
public:
    TemporaryMainMenuWithStandardCommands()
        : oldMenu (MenuBarModel::getMacMainMenu()), oldAppleMenu (nullptr)
    {
        const PopupMenu* appleMenu = MenuBarModel::getMacExtraAppleItemsMenu();
        if (appleMenu != nullptr)
            oldAppleMenu = new PopupMenu (*appleMenu);

        MenuBarModel::setMacMainMenu (nullptr);

        NSMenu* menu = [[NSMenu alloc] initWithTitle: nsStringLiteral ("Edit")];
        NSMenuItem* item;

        item = [[NSMenuItem alloc] initWithTitle: NSLocalizedString (nsStringLiteral ("Cut"), nil)
                                          action: @selector (cut:)  keyEquivalent: nsStringLiteral ("x")];
        [menu addItem: item];
        [item release];

        item = [[NSMenuItem alloc] initWithTitle: NSLocalizedString (nsStringLiteral ("Copy"), nil)
                                          action: @selector (copy:)  keyEquivalent: nsStringLiteral ("c")];
        [menu addItem: item];
        [item release];

        item = [[NSMenuItem alloc] initWithTitle: NSLocalizedString (nsStringLiteral ("Paste"), nil)
                                          action: @selector (paste:)  keyEquivalent: nsStringLiteral ("v")];
        [menu addItem: item];
        [item release];

        item = [[NSApp mainMenu] addItemWithTitle: NSLocalizedString (nsStringLiteral ("Edit"), nil)
                                          action: nil  keyEquivalent: nsEmptyString()];
        [[NSApp mainMenu] setSubmenu: menu forItem: item];
        [menu release];
    }

    ~TemporaryMainMenuWithStandardCommands()
    {
        MenuBarModel::setMacMainMenu (oldMenu, oldAppleMenu);
    }

private:
    MenuBarModel* oldMenu;
    ScopedPointer<PopupMenu> oldAppleMenu;
};

//==============================================================================
void FileChooser::showPlatformDialog (Array<File>& results,
                                      const String& title,
                                      const File& currentFileOrDirectory,
                                      const String& filter,
                                      bool selectsDirectory,
                                      bool selectsFiles,
                                      bool isSaveDialogue,
                                      bool /*warnAboutOverwritingExistingFiles*/,
                                      bool selectMultipleFiles,
                                      FilePreviewComponent* /*extraInfoComponent*/)
{
    JUCE_AUTORELEASEPOOL

    const TemporaryMainMenuWithStandardCommands tempMenu;

    StringArray* filters = new StringArray();
    filters->addTokens (filter.replaceCharacters (",:", ";;"), ";", String::empty);
    filters->trim();
    filters->removeEmptyStrings();

   #if defined (MAC_OS_X_VERSION_10_6) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_6
    typedef NSObject<NSOpenSavePanelDelegate> DelegateType;
   #else
    typedef NSObject DelegateType;
   #endif

    static FileChooserDelegateClass cls;
    DelegateType* delegate = (DelegateType*) [[cls.createInstance() init] autorelease];
    FileChooserDelegateClass::setFilters (delegate, filters);

    NSSavePanel* panel = isSaveDialogue ? [NSSavePanel savePanel]
                                        : [NSOpenPanel openPanel];

    [panel setTitle: juceStringToNS (title)];

    if (! isSaveDialogue)
    {
        NSOpenPanel* openPanel = (NSOpenPanel*) panel;
        [openPanel setCanChooseDirectories: selectsDirectory];
        [openPanel setCanChooseFiles: selectsFiles];
        [openPanel setAllowsMultipleSelection: selectMultipleFiles];
        [openPanel setResolvesAliases: YES];
    }

    [panel setDelegate: delegate];

    if (isSaveDialogue || selectsDirectory)
        [panel setCanCreateDirectories: YES];

    String directory, filename;

    if (currentFileOrDirectory.isDirectory())
    {
        directory = currentFileOrDirectory.getFullPathName();
    }
    else
    {
        directory = currentFileOrDirectory.getParentDirectory().getFullPathName();
        filename = currentFileOrDirectory.getFileName();
    }

   #if defined (MAC_OS_X_VERSION_10_6) && (MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_6)
    [panel setDirectoryURL: [NSURL fileURLWithPath: juceStringToNS (directory)]];
    [panel setNameFieldStringValue: juceStringToNS (filename)];

    if ([panel runModal] == NSOKButton)
   #else
    if ([panel runModalForDirectory: juceStringToNS (directory)
                               file: juceStringToNS (filename)] == NSOKButton)
   #endif
    {
        if (isSaveDialogue)
        {
            results.add (File (nsStringToJuce ([[panel URL] path])));
        }
        else
        {
            NSOpenPanel* openPanel = (NSOpenPanel*) panel;
            NSArray* urls = [openPanel URLs];

            for (unsigned int i = 0; i < [urls count]; ++i)
                results.add (File (nsStringToJuce ([[urls objectAtIndex: i] path])));
        }
    }

    [panel setDelegate: nil];
}

bool FileChooser::isPlatformDialogAvailable()
{
    return true;
}

#else

//==============================================================================
bool FileChooser::isPlatformDialogAvailable()
{
    return false;
}

void FileChooser::showPlatformDialog (Array<File>& results,
                                      const String& title,
                                      const File& currentFileOrDirectory,
                                      const String& filter,
                                      bool selectsDirectory,
                                      bool selectsFiles,
                                      bool isSaveDialogue,
                                      bool warnAboutOverwritingExistingFiles,
                                      bool selectMultipleFiles,
                                      FilePreviewComponent* extraInfoComponent)
{
    JUCE_AUTORELEASEPOOL

    jassertfalse; //there's no such thing in iOS
}

#endif
