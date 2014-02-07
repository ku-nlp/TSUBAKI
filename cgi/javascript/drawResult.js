var FONT_SIZE  = 11;
var ARROW_SIZE = 4;
var GRAPHICS;

var NECCESARY   = 0;
var OPTIONAL    = 1;
var UNNECCESARY = 2;

var termGroups;
var canvasName = '';
var IMPORTANCE_CHARS = new Array ("○", "△", "×");

var PALE_COLOR = new Array ("#ffff99", "#bbffff", "#ffbbff", "#ffbbbb", "#bbffbb", "#bb0000", "#00bb00", "#bbbb00", "#00bbbb", "#bb00bb");
var DARK_COLOR = new Array ("#ffa500", "#000080", "#997799", "#800000", "#779977", "#770000", "#007700", "#777700", "#007777", "#770077");
var FOREGROUND = new Array ("#000000", "#000000", "#000000", "#000000", "#000000", "#ffffff", "#ffffff", "#ffffff", "#ffffff", "#ffffff");
var BACKGROUND = new Array ("#ffffcb", "#edffff", "#ffedff", "#efdddd", "#edffed", "#ed3030", "#30ed30", "#eeee30", "#30eeee", "#ee30ee");

function init2 (_canvasName) {
    canvasName = _canvasName;
}

function setTermGroups (_termGroups) {
    termGroups = _termGroups;
}

function paint () {
    var htmlCode = '';
    for (var i = 0; i < termGroups.length; i++) {
        htmlCode += termGroups[i].paint();
    }
    Element.update(canvasName, htmlCode);

    GRAPHICS = new jsGraphics(canvasName);
    GRAPHICS.setFont('ＭＳゴシック', "10pt", 0);
    GRAPHICS.clear();

    for (var i = 0; i < termGroups.length; i++) {
	termGroups[i].drawDependency();
    }

    for (var i = 0; i < termGroups.length; i++) {
	termGroups[i].drawImportance();
    }
    GRAPHICS.paint();
}

function showQueryEditWindow () {
    document.getElementById('query_edit_window').style.display = "block";
    paint();
}

function hideQueryEditWindow () {
    document.getElementById('query_edit_window').style.display = "none";
}

function onclickPerformed (id) {
    var ids = id.split("-");
    termGroups[ids[0]].onclick(ids[1]);
}

function Term (initState, id, synid, strings, type, color) {
    this.id = id;
    this.synid = synid;
    this.strings = strings;
    this.type = type;
    this.color = color;
    this.state = initState;
    this.fgcolor = FOREGROUND[this.color];
    this.bgcolor = BACKGROUND[this.color];
    this.borderColor = DARK_COLOR[this.color];
  
    this.paint = function () {
	if (type == "basic") {
	    return ("<DIV class='termBasic' style='border-bottom: 1px solid " + DARK_COLOR[this.color] + ";'>" + this.strings + "</DIV>");
	} else {
            var _buf = new Array();
            for (var i = 0; i < this.strings.length; i++) {
                if (i < 5) {
                    _buf.push(this.strings[i]);
                } else {
                    _buf.push("：");
                    break;
                }
            }

            if (this.state % 2) {
	        return ("<DIV id=" + this.id + " onclick='onclickPerformed(this.id)' class='term' style='cursor: pointer; color:" + this.fgcolor + "; background-color:" + this.bgcolor + "; border: 1px solid " + this.borderColor + ";'>" + _buf.join("<BR>") + "</DIV>");
            } else {
	        return ("<DIV id=" + this.id + " onclick='onclickPerformed(this.id)' class='term' style='cursor: pointer; color: gray; background-color: lightGray; border: 1px solid " + this.borderColor + ";'>" + _buf.join("<BR>") + "</DIV>");
            }
	}
    }

    this.disable = function () {
	document.getElementById(this.id).style.color = "gray";
	document.getElementById(this.id).style.backgroundColor = "lightGray";
	this.state = 0;
    }

    this.enable = function () {
	document.getElementById(this.id).style.color = this.fgcolor;
	document.getElementById(this.id).style.backgroundColor = this.bgcolor;
	this.state = 1;
    }

    this.onclick = function () {
        this.state++;
        this.repaint();
    }
  
    this.width = function () {
	var maxWidth = 0;
	if (type == "basic") {
	    maxWidth = this.strings.length;
        } else { 
	    maxWidth = this.strings[0].length;
            for (var i = 0; i < this.strings.length; i++) {	
                var string = this.strings[i];
	        if (maxWidth < string.length) {
	            maxWidth = string.length;
                }
            }
        }
	return maxWidth;
    }

    this.getState = function () {
	return (this.state % 2);
    }

    this.getSynID = function () {
	return this.synid;
    }

    this.repaint = function () {
	if (this.state % 2) {
	    this.enable();
	} else {
	    this.disable();
	}
    }
}

function TermGroup (id, basicWord, importance) {
    this.id = id;
    this.basicWord = basicWord;
    this.importance = importance;
    this.child_id = 0;
    this.children = new Array();
    this.dependancy = new Array();
    this.fgcolor = DARK_COLOR[this.id];
    this.bgcolor = PALE_COLOR[this.id];

    this.children.push(new Term(1, this.id + "-" + this.child_id, "", basicWord, "basic", this.id));

    this.drawImportance = function () {
	var string = "<DIV class='imp' id='" + this.id + "-imp' onclick='onclickPerformed(this.id)'>" + IMPORTANCE_CHARS[this.importance] + "</DIV>";
	GRAPHICS.drawStringRect(string, this.getX(), this.getY() - (1.4 * FONT_SIZE), FONT_SIZE * 2, 'right');
	for (var i = 0; i < this.dependancy.length; i++) {
	    this.dependancy[i].drawImportance();
	}
    }

    this.setDependency = function (dpnd) {
	this.dependancy = dpnd;
	for (var i = 0; i < dpnd.length; i++) {
	    this.child_id++;
	    this.dependancy[i].setID(this.id + "-" + this.child_id);
	}
    }

    this.getDependency = function (dpnd) {
	return this.dependancy;
    }

    this.drawDependency = function () {
	for (var i = 0; i < this.dependancy.length; i++) {
	    this.dependancy[i].paint(i * ARROW_SIZE, 'black');
	}
    }

    this.onclick = function (child_id) {
	if (child_id == "imp") {
	    this.importance = (this.importance + 1)%IMPORTANCE_CHARS.length;
	    document.getElementById(this.id + "-imp").innerHTML = IMPORTANCE_CHARS[this.importance];
	    if (this.importance == UNNECCESARY) {
		document.getElementById(this.id).style.color = "gray";
		document.getElementById(this.id).style.backgroundColor = "lightGray";
		document.getElementById(this.id).style.borderColor = "gray";
	    } else {
		document.getElementById(this.id).style.color = "black";
		document.getElementById(this.id).style.backgroundColor = this.bgcolor;
		document.getElementById(this.id).style.borderColor = this.fgcolor;
	    }

	    // skip basic word
	    for (var i = 1; i < this.children.length; i++) {
		if (this.importance == UNNECCESARY) {
		    this.children[i].disable();
		} else {
		    this.children[i].enable();
		}
	    }
	}
	else if (child_id < this.children.length) {
	    this.children[child_id].onclick();
	} else {
	    this.dependancy[child_id - this.children.length].onclick();
	}
    }
  
    this.push = function (initState, synid, strings) {
	this.child_id++;
	this.children.push(new Term(initState, this.id + "-" + this.child_id, synid, strings, "syn", this.id));
    }

    this.getID = function () {
	return this.id;
    }

    this.repaint = function () {
	for (var i = 0; i < this.children.length; i++) {
	     this.children[i].repaint();
        }
    }

    this.paint = function () {
	var buf = "";
	var maxWidth = this.children[0].width();
	if (this.importance == UNNECCESARY) {
	    buf = "<DIV id='" + this.id + "' class='termGroup' style='width: " + (maxWidth + 1) + "em; border: 2px solid gray; background-color: lightGray;'>" + this.basicWord + "</DIV>";
	} else {
	    for (var i = 0; i < this.children.length; i++) {
		if (this.children[i].width() > maxWidth) {
		    maxWidth = this.children[i].width();
		}
		buf += this.children[i].paint();
	    }
	    buf = "<DIV id='" + this.id + "' class='termGroup' style='width: " + (maxWidth + 1) + "em; border: 2px solid " + DARK_COLOR[this.id] + "; background-color:" + PALE_COLOR[this.id] + ";'>" + buf + "</DIV>";
	}
	return buf;
    }

    this.getState = function () {
        var states = new Array();
	for (var i = 1; i < this.children.length; i++) {
	    states[i - 1] = this.children[i].getSynID() + "=" + this.children[i].getState();
	}
        return states.join(",");
    }

    this.getImportance = function () {
	return this.importance;
    }

    this.getX = function () {
	return document.getElementById(this.id).offsetLeft;
    }

    this.getCX = function () {
	return document.getElementById(this.id).offsetLeft + this.getWidth() / 2;
    }

    this.getY = function () {
	return document.getElementById(this.id).offsetTop;
    }

    this.getWidth = function () {
	return document.getElementById(this.id).offsetWidth;
    }

    this.getHeight = function () {
	return document.getElementById(this.id).offsetHeight;
    }
}

function Dependency (parent, child, importance) {
    this.id = 0;
    this.parent = parent;
    this.child = child;
    this.importance = importance;
    this.dist = 3 * (this.parent.getID() - this.child.getID());
    this.height = 0;
    this.offsetX = 0;

    this.onclick = function () {
	this.paint(this.offsetX, "white");
	this.importance = (this.importance + 1)%IMPORTANCE_CHARS.length;
	document.getElementById(this.id).innerHTML = IMPORTANCE_CHARS[this.importance];
	this.paint(this.offsetX, "black");
	GRAPHICS.paint();
    }

    this.setID = function (id) {
	this.id = id;
    }

    this.getParent = function () {
	this.parent;
    }

    this.getChild = function () {
	this.child;
    }

    this.getImportance = function () {
	return this.importance;
    }

    this.drawImportance = function () {
	var top  = document.getElementById(canvasName).style.top;
	var _top = this.height - (1.4 * FONT_SIZE);
	var string = "<DIV class='imp' id='" + this.id + "' onclick='onclickPerformed(this.id)'>" + IMPORTANCE_CHARS[this.importance] + "</DIV>";
	GRAPHICS.drawStringRect(string, this.offsetX + child.getCX(), _top, FONT_SIZE * 2 + 5, 'right');
    }

    this.getHeight = function () {
	return this.height;
    }

    this.paint = function (offsetX, color) {
	GRAPHICS.setColor(color);
	this.offsetX = offsetX;
	if (this.importance == UNNECCESARY) {
	    GRAPHICS.setStroke(Stroke.DOTTED);
	} else {
	    GRAPHICS.setStroke(1);
	}
	this.height = this.parent.getY() - (this.dist) * FONT_SIZE;
        var gap = 5;

	this.drawVLine(this.parent.getCX() - offsetX, this.parent.getY(), this.parent.getCX() - offsetX, this.height);
	this.drawHLine(this.parent.getCX() - offsetX, this.height, this.child.getCX() + offsetX + gap, this.height);
	this.drawVLine(this.child.getCX()  + offsetX + gap, this.child.getY(), this.child.getCX() + offsetX + gap, this.height);
	this.drawArrow(this.parent.getCX() - offsetX, this.parent.getY());
    }

    this.drawArrow = function (x, y) {
	GRAPHICS.fillPolygon(new Array(x, x + ARROW_SIZE, x - ARROW_SIZE), new Array(y, y - ARROW_SIZE, y - ARROW_SIZE));
    }

    this.drawVLine = function (x1, y1, x2, y2) {
	GRAPHICS.drawLine(x1 + 1, y1, x2 + 1, y2);
	GRAPHICS.drawLine(x1, y1, x2, y2);
    }

    this.drawHLine = function (x1, y1, x2, y2) {
	GRAPHICS.drawLine(x1, y1 + 1, x2, y2 + 1);
	GRAPHICS.drawLine(x1, y1, x2, y2);
    }
}
