/*
  ==============================================================================

    Base64.cpp
    Created: 26 Jun 2012 9:06:43pm
    Author:  Joe Fitzpatrick

  ==============================================================================
*/

#include "Base64.h"

char Base64::encodeTable[] = { 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H',
                               'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P',
                               'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X',
                               'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f',
                               'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n',
                               'o', 'p', 'q', 'r', 's', 't', 'u', 'v',
                               'w', 'x', 'y', 'z', '0', '1', '2', '3',
                               '4', '5', '6', '7', '8', '9', '+', '/' };

String Base64::encode(const void* data, size_t numBytes)
{
    return encode (MemoryBlock (data, numBytes));
}

String Base64::encode (const MemoryBlock& data)
{
    String ret (String::empty);
    
    size_t dataSize = data.getSize();
    
    for (size_t i = 0; i < dataSize;)
    {
        uint8 octet_a = i < dataSize ? data[i++] : 0;
        uint8 octet_b = i < dataSize ? data[i++] : 0;
        uint8 octet_c = i < dataSize ? data[i++] : 0;
        
        uint32 triple = (octet_a << 0x10) + (octet_b << 0x08) + octet_c;
        
        ret += encodeTable[(triple >> 3 * 6) & 0x3F];
        ret += encodeTable[(triple >> 2 * 6) & 0x3F];
        ret += encodeTable[(triple >> 1 * 6) & 0x3F];
        ret += encodeTable[(triple >> 0 * 6) & 0x3F];
    }
    
    // Mark trailing padding with '='
    int mod = dataSize % 3;
    
    if (mod)
    {
        int drop = 3 - mod;
        
        ret = ret.dropLastCharacters (drop);
        
        for (int i=0; i < drop ; i++)
            ret += '=';
    }
    
    return ret;
}

uint8 Base64::lookup (const char c)
{
    // Slow!
    for (uint8 n = 0; n < 64 ; n++)
    {
        if (c == encodeTable[n])
            return n;
    }
    
    return 0;
}

MemoryBlock Base64::decode (const String data)
{
    MemoryBlock output;
    
    size_t inLength = data.length();

    // If the string isn't padded to a four byte boundary, don't bother
    if (inLength % 4)
        return output;
    
    // Calc the converted length
    size_t outLength = inLength / 4 * 3;
    
    // Adjust for any padding
    if (data.endsWith ("=="))
        outLength -= 2;
    else if (data.endsWith ("="))
        outLength -= 1;
    
    // Adjust our output block
    output.setSize (outLength);
    
    for (int i = 0, j = 0; i < inLength;)
    {
        uint8 sextet_a = data[i] == '=' ? 0 : lookup (data[i]); ++i;
        uint8 sextet_b = data[i] == '=' ? 0 : lookup (data[i]); ++i;
        uint8 sextet_c = data[i] == '=' ? 0 : lookup (data[i]); ++i;
        uint8 sextet_d = data[i] == '=' ? 0 : lookup (data[i]); ++i;
        
        uint32 triple = (sextet_a << 3 * 6)
                      + (sextet_b << 2 * 6)
                      + (sextet_c << 1 * 6)
                      + (sextet_d << 0 * 6);
        
        if (j < outLength) output[j++] = (triple >> 2 * 8) & 0xff;
        if (j < outLength) output[j++] = (triple >> 1 * 8) & 0xff;
        if (j < outLength) output[j++] = (triple >> 0 * 8) & 0xff;
    }
    
    return output;
}

