<#assign myImg=""/>
<#if (.data_model["ObjectRelationship#C_MyTeacher#myTeacherToMyCourseTeacher_photo"].getData())??>
	<#assign myImg=.data_model["ObjectRelationship#C_MyTeacher#myTeacherToMyCourseTeacher_photo"].getData()/>
	<#if (myImg!="")>
		<#assign myDoc = restClient.get("/headless-delivery/v1.0/documents/${myImg}")/>
	</#if>
	<#if (myDoc??)>
		<img src="${myDoc.contentUrl}"/>
	</#if>
</#if>