/*
  ==============================================================================

    AmazonS3.h
    Created: 27 Jun 2012 1:25:29pm
    Author:  Joe Fitzpatrick

  ==============================================================================
*/

#ifndef __AMAZONS3_H_CCA7A5D2__
#define __AMAZONS3_H_CCA7A5D2__

#include "../JuceLibraryCode/JuceHeader.h"

class AmazonS3
{
public:
    AmazonS3 (const String& credentials_, const String& secret_)
    :  credentials (credentials_),
       secret (secret_) {}
    
    ~AmazonS3() {}


    String createURL (const String& verb, const String& bucket, const String& objectID);

private:
    String credentials;
    String secret;
    
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (AmazonS3)        
};



#endif  // __AMAZONS3_H_CCA7A5D2__
