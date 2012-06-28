/*
  ==============================================================================

    AmazonS3.cpp
    Created: 27 Jun 2012 1:25:29pm
    Author:  Joe Fitzpatrick

  ==============================================================================
*/

#include "HMAC_SHA1.h"
#include "Base64.h"
#include "AmazonS3.h"

String AmazonS3::createURL (const String& verb, const String& bucket, const String& objectID)
{
    // Create a signiture

    String expires ((Time::getCurrentTime().toMilliseconds() / 1000) + 300);
    String canonicalizedResource = "/" + bucket + "/" + objectID;

    String signString = verb.toUpperCase() + "\n\n\n" + 
                        expires + "\n" + 
                        canonicalizedResource;
    
    
    String signature = URL::addEscapeChars (Base64::encode (HMAC_SHA1().encode (signString, secret)), true);

    String url = "https://" + bucket + ".s3.amazonaws.com/" + objectID +
                 "?AWSAccessKeyId=" + URL::addEscapeChars(credentials, true) +
                 "&" + "Expires=" + expires + "&Signature=" + signature;
    
    return url;
}
