#!/usr/bin/ruby

inFile = $*.first
outFile = $*[1].to_s

fileIn = open(inFile)
fileOut = open(outFile, "w")

startP = endP = 0

for line in fileIn do
   if line == "\n"
      startP = endP + 1
   else
      line.gsub!(/STDIN:[0-9]+\s/, "")
      cells = line.split(/\t/)
      cells[0] = cells[0].to_i + startP
      cells[1] = cells[1].to_i + startP
      if endP < cells[1]
         endP = cells[1]
      end
      line = cells.join("\t")
      fileOut << line
   end
end
