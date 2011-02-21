#!/usr/bin/ruby

inFile = $*[0].to_s # non-split raw text
inFile2 = $*[1].to_s # split raw text
inFile3 = $*[2].to_s # enju original output
outFile = $*[3].to_s # output converted for non-split text

fileIn = open(inFile)
fileIn2 = open(inFile2)
fileIn3 = open(inFile3)
fileOut = open(outFile, "w")

readCount = 0
diff = 0

for line in fileIn3 do
   cells = line.split(/\t/)
#   p ("in readCount " + readCount.to_s)

   while readCount <= cells[0].to_i do
      c1 = fileIn.getc
      c2 = fileIn2.getc
      readCount += 1
 #     p [c1, c2]
      while c1 != c2
         if c2 == '\n'
            c2 = fineIn2.getc
            readCount += 1
            diff -= 1
         else
            c1 = fileIn.getc
            diff += 1
         end
      end
   end

   cells[0] = cells[0].to_i + diff

   while readCount <= cells[1].to_i do
#      if fileIn.eof? or fileIn2.eof?
#         break
#      end
      c1 = fileIn.getc
      c2 = fileIn2.getc
      readCount += 1
 #     p [c1, c2.chr]
 #     p readCount
      while c1 != c2
         if c2.chr == "\n"
            c2 = fileIn2.getc
#            p [c1, c2]
            readCount += 1
            diff -= 1
         else
            c1 = fileIn.getc
            diff += 1
         end
      end
   end

   cells[1] = cells[1].to_i + diff

   line = cells.join("\t")
   fileOut << line
end
