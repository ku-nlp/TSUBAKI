CommandHandler.o:
OptionParser.o: OptionParser.hpp
Mapper.o: Mapper.hpp TagData.hpp
main.o: CommandHandler.hpp SortHandler.hpp OptionParser.hpp \
 MergeHandler2.hpp Verifier.hpp
MergeHandler2.o: som_util.hpp OptionParser.hpp \
 TagData.hpp MergeHandler2.hpp CommandHandler.hpp
som_util.o: som_util.hpp OptionParser.hpp
SortHandler.o: CommandHandler.hpp SortHandler.hpp \
 OptionParser.hpp StandOffManager.hpp TagData.hpp som_util.hpp
StandOffManager.o: StandOffManager.hpp TagData.hpp \
 Mapper.hpp
TagData.o: TagData.hpp
Verifier.o: TagData.hpp som_util.hpp OptionParser.hpp \
 Verifier.hpp CommandHandler.hpp
