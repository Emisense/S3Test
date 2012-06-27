/*
  ==============================================================================

    HMAC_SHA1.h
    Created: 27 Jun 2012 7:48:28am
    Author:  Joe Fitzpatrick

  ==============================================================================
*/

#ifndef __HMAC_SHA1_H_FA662243__
#define __HMAC_SHA1_H_FA662243__

#include "SHA1.h"

class HMAC_SHA1 : public SHA1
{
public:
    
    
    HMAC_SHA1()
      :  szReport(new char[HMAC_BUF_LEN]),
         SHA1_Key(new char[HMAC_BUF_LEN]),
         AppendBuf1(new char[HMAC_BUF_LEN]),
         AppendBuf2(new char[HMAC_BUF_LEN]) {}
    
    ~HMAC_SHA1()
    {
        delete[] szReport;
        delete[] AppendBuf1;
        delete[] AppendBuf2;
        delete[] SHA1_Key;
    }
    
    MemoryBlock encode (const char* text, int text_len, const char* key, int key_len);
    MemoryBlock encode (const String& text, const String& key);
    
private:
    uint8 m_ipad[64];
    uint8 m_opad[64];
    
    char* szReport;
    char* SHA1_Key;
    char* AppendBuf1;
    char* AppendBuf2;
    
    
    enum {
        SHA1_DIGEST_LENGTH	= 20,
        SHA1_BLOCK_SIZE		= 64,
        HMAC_BUF_LEN		= 4096
    } ;
    
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (HMAC_SHA1)    
};


#endif  // __HMAC_SHA1_H_FA662243__
