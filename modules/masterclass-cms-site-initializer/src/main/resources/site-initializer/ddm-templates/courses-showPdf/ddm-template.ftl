<#if (ObjectField_courseOnePagerSheet.getData())??>
	<#assign mydocID=ObjectField_courseOnePagerSheet.getData()/>
	<#assign myDoc = (restClient.get("/headless-delivery/v1.0/documents/" + mydocID))!{}/>
	<#if (myDoc.contentUrl)??>
		${myDoc.contentUrl}
	</#if>
</#if>
