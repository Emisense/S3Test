/*
  ==============================================================================

    HMAC_SHA1.cpp
    Created: 27 Jun 2012 7:48:28am
    Author:  Joe Fitzpatrick

  ==============================================================================
*/

#include "HMAC_SHA1.h"

MemoryBlock HMAC_SHA1::encode (const String& text, const String& key)
{
    return encode (text.toUTF8(), text.length(), key.toUTF8(), key.length());
}

MemoryBlock HMAC_SHA1::encode (const char* text, int text_len, const char* key, int key_len)
{
	memset(SHA1_Key, 0, SHA1_BLOCK_SIZE);
    
	/* repeated 64 times for values in ipad and opad */
	memset(m_ipad, 0x36, sizeof(m_ipad));
	memset(m_opad, 0x5c, sizeof(m_opad));
    
	/* STEP 1 */
	if (key_len > SHA1_BLOCK_SIZE)
	{
		SHA1::reset();
		SHA1::update(key, key_len);
		MemoryBlock b = SHA1::finalize();
        b.copyTo (SHA1_Key, 0, b.getSize());
	}
	else
		memcpy(SHA1_Key, key, key_len);
    
	/* STEP 2 */
	for (int i=0; i<sizeof(m_ipad); i++)
	{
		m_ipad[i] ^= SHA1_Key[i];		
	}
    
	/* STEP 3 */
	memcpy(AppendBuf1, m_ipad, sizeof(m_ipad));
	memcpy(AppendBuf1 + sizeof(m_ipad), text, text_len);
    
	/* STEP 4 */
	SHA1::reset();
	SHA1::update((uint8 *)AppendBuf1, sizeof(m_ipad) + text_len);
	MemoryBlock b = SHA1::finalize();
    b.copyTo (szReport, 0, b.getSize());
    
	/* STEP 5 */
	for (int j=0; j<sizeof(m_opad); j++)
	{
		m_opad[j] ^= SHA1_Key[j];
	}
    
	/* STEP 6 */
	memcpy(AppendBuf2, m_opad, sizeof(m_opad));
	memcpy(AppendBuf2 + sizeof(m_opad), szReport, SHA1_DIGEST_LENGTH);
    
	/*STEP 7 */
	SHA1::reset();
	SHA1::update((uint8 *)AppendBuf2, sizeof(m_opad) + SHA1_DIGEST_LENGTH);
    return SHA1::finalize();
}
