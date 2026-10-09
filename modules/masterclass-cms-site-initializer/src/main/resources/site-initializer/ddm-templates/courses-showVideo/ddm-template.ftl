<#if (ObjectField_referenceVideo.getData())??>
	<#assign mydocID=ObjectField_referenceVideo.getData()/>
	<#assign myVideo = (restClient.get("/headless-delivery/v1.0/documents/" + mydocID))!{}/>
	<#if (myVideo.contentUrl)??>
		${myVideo.contentUrl}
	</#if>
</#if>
