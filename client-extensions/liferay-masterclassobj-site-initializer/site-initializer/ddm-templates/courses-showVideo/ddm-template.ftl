<#if (ObjectField_representativeImage.getData())??>
	<#assign mydocID=ObjectField_representativeVideo.getData()/>
	<#assign myImage = restClient.get("/headless-delivery/v1.0/documents/" + mydocID)/>
	<#if myImage??>
		${myImage.contentUrl}
	</#if>
</#if>