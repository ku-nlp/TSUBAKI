#ifndef STAND_OFF_MANAGER_HPP
#define STAND_OFF_MANAGER_HPP

#include <iostream>
#include <string>
#include <vector>
#include <set>

#include "TagData.hpp"

class StandOffManager{
public:
    StandOffManager(void) {}

	//--------------------------------------------------------------------------
	// functions to read/write standoff data
	//--------------------------------------------------------------------------
    void readDataStrictly(std::istream &is);

    void readData(const std::string &filename);
    void readData(std::istream& is);

    void writeData(const std::string &filename);
    void writeData(std::ostream &os);

	//--------------------------------------------------------------------------
	// Getter
	//--------------------------------------------------------------------------
    void getData(std::vector<TagData> &data) const;

	//--------------------------------------------------------------------------
	// read tag order list
	//--------------------------------------------------------------------------
    void readTagOrder(const std::string &filename);
    void readTagOrder(std::istream &is);

	//--------------------------------------------------------------------------
	// function for the import operation
	//--------------------------------------------------------------------------
    void readSemiXMLandWriteRawText(std::istream &is, std::ostream &os);

	//--------------------------------------------------------------------------
	// function for the export operation
	//--------------------------------------------------------------------------
    void writeSemiXML(std::istream& rawTxt, std::ostream& semiXML);
    static void writeSemiXML(std::istream &rawTxt, std::istream &isSoff, std::ostream &semiXML);

	//--------------------------------------------------------------------------
	// verify the well-formedness
	//--------------------------------------------------------------------------
    bool checkDataConsistency(void);

	//--------------------------------------------------------------------------
	// function for the sort operation
	//--------------------------------------------------------------------------
    void sort(void);

	//--------------------------------------------------------------------------
	//
	//--------------------------------------------------------------------------
    void integrateFiles(
		const std::string &filename1,
		const std::string &filename2);

	//--------------------------------------------------------------------------
	// function for the clip operation
	//--------------------------------------------------------------------------
    void clipData(
		const std::string &standoffFile1,
		const std::string &txtFile1,
		const std::string &tagFile,
		const std::string &standoffFile2,
		const std::string &txtFile2);

    void clipData(
		std::istream &isSoff,
		std::istream &isTxt,
		std::istream &isTag,
        std::ostream &osSoff,
		std::ostream &osTxt);

	//--------------------------------------------------------------------------
	// function for the unite operation
	//--------------------------------------------------------------------------
    void readConformedPositions(
		const std::string &strictFile,
		const std::string &partialFile);

    void readConformedPositions(
		std::istream &isSoffStrict,
		std::istream &isSoffPartial);

    void readConformedPositions(
		std::istream &isSoffStrict,
		std::istream &isSoffPartial,
        std::ostream &out);

	//--------------------------------------------------------------------------
	// function for the merge operation
	//--------------------------------------------------------------------------
    StandOffManager& operator+=(const StandOffManager &a);

	//--------------------------------------------------------------------------
	// 
	//--------------------------------------------------------------------------
	unsigned getNumTags(void) const { return tagsData.size(); }

private:
    std::vector<std::string> tagOrder;
    std::vector<TagData> tagsData;
};


#endif /*STANDOFFMANAGER_HPP*/

