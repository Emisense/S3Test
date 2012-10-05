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
class S3ObjectInfo
{
public:
    //==============================================================================
    S3ObjectInfo() {}
    
    S3ObjectInfo (const String& header_)
    :  header (header_) {}
    
    ~S3ObjectInfo() {}
    
    //==============================================================================
    bool isSuccess();
    bool isValid();
    
    String getResult();
    
    int getLength();
    String getMD5();
    
    String getRawHeader() { return header; }
    
    static const S3ObjectInfo empty;
    
private:
    //==============================================================================
    String header;
    
    //==============================================================================
    JUCE_LEAK_DETECTOR(S3ObjectInfo)
};


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
    String getBucket() const     { return bucket; }
    String getId() const         { return objectId; }
    S3ObjectInfo getInfo() const { return lastInfo; }
    File getFile() const         { return lastFile; }
    
    void setBucket (const String& bucket_) 
    { 
        bucket = bucket_;
        lastFile = File::nonexistent;
        lastInfo = S3ObjectInfo();
    }
    
    void setId (const String& objectId_)
    { 
        objectId = objectId_; 
        lastFile = File::nonexistent;
        lastInfo = S3ObjectInfo();    
    }
    
    bool isSuccess()   { return lastInfo.isSuccess(); }
    String getResult() { return lastInfo.getResult(); }

        void clearFileAndInfo() { lastFile = File::nonexistent; lastInfo = S3ObjectInfo::empty; }
    void setFile (const File& file)         { lastFile = file; }
    void setInfo (const S3ObjectInfo& info) { lastInfo = info; }
    
private:
    //==============================================================================
    String bucket;
    String objectId;

    S3ObjectInfo lastInfo;
    File lastFile;
    
    //==============================================================================
    JUCE_LEAK_DETECTOR(S3Object)
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
    bool updateObjectInfo (S3Object& object);
    
    bool getObject (S3Object& object, const File& file);
    bool putObject (S3Object& object, const File& file, bool makePublic = false);
    
    //==============================================================================
    bool getDirectory (const String& bucket, StringArray& list);
    
private:    
    //==============================================================================
    String createURL (const String& verb, const S3Object& object, const String& amzHeader = String::empty);
    String runCurl (const String& cmdLine);
    
private:
    //==============================================================================
    String credentials;
    String secret;
    
    //==============================================================================
    JUCE_LEAK_DETECTOR (AmazonS3)        
};



#endif  // __AMAZONS3_H_CCA7A5D2__
