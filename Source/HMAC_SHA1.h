/*
  ==============================================================================

    HMAC_SHA1.h
    Created: 27 Jun 2012 7:48:28am
    Author:  Joe Fitzpatrick

  ==============================================================================
*/

#ifndef __HMAC_SHA1_H_FA662243__
#define __HMAC_SHA1_H_FA662243__

#include "../JuceLibraryCode/JuceHeader.h"


//==============================================================================
//==============================================================================
class HMAC_SHA1
{
public:
    //==============================================================================
    HMAC_SHA1() {}
    ~HMAC_SHA1() {}
    
    //==============================================================================
    static MemoryBlock encode (const char* text, int textLen, const char* key, int keyLen);
    static MemoryBlock encode (const String& text, const String& key);
    
private:
    //==============================================================================
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (HMAC_SHA1)    
};


#endif  // __HMAC_SHA1_H_FA662243__
