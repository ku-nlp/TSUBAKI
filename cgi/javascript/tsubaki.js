function send_questionnarie () {
    var q = document.search.qbox.value;
    var question = -1;
    for (var i = 0; i < document.questionnarieForm.question.length; i++) {
	if (document.questionnarieForm.question[i].checked) {
	    question = document.questionnarieForm.question[i].value;
	}
    }
    var msg = document.questionnarieForm.message.value;

    var param = "q=" + q + "&question=" + question + "&msg=" + msg;
    new Ajax.Request("http://nlpc06.ixnlp.nii.ac.jp/cgi-bin/tsubaki-develop/questionnarie.cgi", {method: 'get', parameters: param, onComplete: complete});
}

function complete (originalRequest) {
    var pane = document.getElementById('questionnaire');
    if (Prototype.Browser.IE) {
	alert("アンケート結果を送信しました。ご協力有難うございました。");
    } else {
	pane.innerHTML = "<TR><TD align='center'>アンケート結果を送信しました。<BR>ご協力有難うございました。</TD></TR>";
    }
}

function toggle_simpage_view (id, obj, open_label, close_label) {
    var disp = document.getElementById(id).style.display;
    if (disp == "block") {
        document.getElementById(id).style.display = "none";
        obj.innerHTML = open_label;
    } else {
        document.getElementById(id).style.display = "block";
        obj.innerHTML = close_label;
    }
}

function hide_query_result () {
    var baroon = document.getElementById("baroon");
    baroon.style.display = "none";
}
