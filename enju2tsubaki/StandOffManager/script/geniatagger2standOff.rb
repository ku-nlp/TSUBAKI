#!/usr/local/bin/ruby

$inputPath = File.expand_path($*.first) #not split txt
$inputPath2 = File.expand_path($*[1].to_s) #pos
$outputPath = File.expand_path($*[2].to_s)

def main
   inFile = open($inputPath)
   inFile2 = open($inputPath2)
   outFile = open($outputPath, "w")
   startP = 0
   endP = 0
   position = 0
   wc = 0
   quatationFlag = false
   cons = ""
   consStartP = 0
   consEndP = 0
   inCons = false

   for line in inFile2 do
      line.chomp!
      if(line != "")
         base, base2, pos, bio, ne = line.split("\t")
         wc += 1
         consEndP = position

         #p ("in word " + base + " " + wc.to_s)
         #if base.match(/''/)
         #elsif base.match(/``/)
         #end
         target = ""
         base.size.times do |i|
            if !quatationFlag
               target = inFile.getc
               #p "a"
               position += 1
            end
            while(target != base[i])
               #p target.to_s
               if((base[i] == "'"[0] or base[i] == "`"[0]) and target == "\""[0])
                  #p "in"
                  if quatationFlag
                     #p "c"
                     quatationFlag = false
                     break
                  else
                     #p "b"
                     quatationFlag = true
                     break
                  end
               else
                  #p "d"
                  target = inFile.getc
                  #print target
                  position += 1
               end
            end
            if(i == 0)
               startP = position - 1
            end
         end

         if bio.match(/^B-(.+)/)
            if inCons
               outFile << consStartP << "\t" << consEndP  << "\t" << "chunk " << "cat=\"" << cons << "\"\n"
            end
            cons = bio.sub(/^B-/, "")
            inCons = true
            consStartP = startP
         end
         if bio.match(/^O$/)
            outFile << consStartP << "\t" << consEndP  << "\t" << "chunk " << "cat=\"" << cons << "\"\n"
            inCons = false
         end

         outFile << startP << "\t" << position  << "\t" << "word " << "pos=\"" << pos << "\" base=\"" << base << "\"\n"
      end
   end
end

main
