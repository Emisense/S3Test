/*
  ==============================================================================

    Base64.h
    Created: 26 Jun 2012 9:06:43pm
    Author:  Joe Fitzpatrick

  ==============================================================================
*/

#ifndef __BASE64_H_2FC8A21D__
#define __BASE64_H_2FC8A21D__

#include "../JuceLibraryCode/JuceHeader.h"

class Base64
{
public:
    static String encode (const void* data, size_t numBytes);
    static String encode (const MemoryBlock& data);
    
    static MemoryBlock decode (const String);
    
private:
    static char encodeTable[];
    static uint8 lookup (const char c);
    
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (Base64)    
};



#endif  // __BASE64_H_2FC8A21D__
