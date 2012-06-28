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

//==============================================================================
//==============================================================================
class S3Object
{
public:
    //==============================================================================
    S3Object() {}
    
    S3Object (const String& bucket_, const String& objectId_)
    : bucket (bucket_),
      objectId (objectId_) {}
  
    ~S3Object() {}
    
    //==============================================================================
    String getBucket() const { return bucket; }
    String getId() const     { return objectId; }

    void setBucket (const String& bucket_) { bucket = bucket_; }
    void setId (const String& objectId_)   { objectId = objectId; }
    
private:
    //==============================================================================
    String bucket;
    String objectId;
    
    //==============================================================================
    JUCE_LEAK_DETECTOR(S3Object)
};


//==============================================================================
//==============================================================================
class S3ObjectInfo
{
public:
    //==============================================================================
    S3ObjectInfo() {}
    
    S3ObjectInfo (const String& header_)
    :  header (header_) {}
    
    ~S3ObjectInfo() {}
    
    //==============================================================================
    bool isValid();
    String resultCode();
    
    int getLength();
    String getMD5();
    
    String getRawHeader() { return header; }
    
private:
    //==============================================================================
    String header;
    
    //==============================================================================
    JUCE_LEAK_DETECTOR(S3ObjectInfo)
};


//==============================================================================
//==============================================================================
class AmazonS3
{
public:
    //==============================================================================
    AmazonS3 (const String& credentials_, const String& secret_)
    :  credentials (credentials_),
       secret (secret_) {}
    
    ~AmazonS3() {}

    //==============================================================================
    S3ObjectInfo getObjectInfo (const S3Object& object);
    
    bool getObject (const S3Object& object, const File& file);
    bool putObject (const S3Object& object, const File& file);
    
private:    
    //==============================================================================
    String createURL (const String& verb, const S3Object& object);
    String runCurl (const String& cmdLine);
    
private:
    //==============================================================================
    String credentials;
    String secret;
    
    //==============================================================================
    JUCE_LEAK_DETECTOR (AmazonS3)        
};



#endif  // __AMAZONS3_H_CCA7A5D2__
