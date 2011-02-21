
#!/usr/bin/ruby

inFile = $*.first
txtFile = $*[1].to_s
outFile = $*[2].to_s

fileIn = open(inFile)
fileIn2 = open(txtFile)
fileOut = open(outFile, "w")

startP = endP = 0

for line in fileIn do
   if line == "\n"
      line2 = fileIn2.gets
      startP += line2.size
   else
      line.gsub!(/STDIN:[0-9]+\s/, "")
      cells = line.split(/\t/)
      cells[0] = cells[0].to_i + startP
      cells[1] = cells[1].to_i + startP
      line = cells.join("\t")
      fileOut << line
   end
end
