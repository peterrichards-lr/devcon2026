const LiferayService = {
  get: async (url) => {
    if (typeof window['Liferay'] != 'undefined') {
      try {
        const response = await window['Liferay'].Util.fetch(url);
        const data = await response.json();
        if (data.status) {
          window['Liferay'].Util.openToast({
            title: data.status,
            message: 'An error occured.',
            type: 'danger',
          });
        } else {
          window['Liferay'].Util.openToast({
            title: 'Success',
            message: 'Your request completed successfully.',
            type: 'success',
          });
          return data;
        }
      } catch (error) {
        console.error(error);
        window['Liferay'].Util.openToast({
          message: 'An error occured.',
          type: 'danger',
        });
      }
    } else {
      console.error("Liferay (JS Object) doesn't exist.");
    }
  },
  post: async (url, payload) => {
    if (typeof window['Liferay'] != 'undefined') {
      try {
        const response = await window['Liferay'].Util.fetch(url, {
          body: JSON.stringify(payload),
          method: `POST`,
          headers: [['content-type', 'application/json']],
        });
        const data = await response.json();
        if (response.status) {
          if (response.status=="403"){
		  window['Liferay'].Util.openToast({
            title: data.status,
            message: 'You need to be logged in to enroll.',
            type: 'danger',
          });			  
		  }else if (response.status=="200"){
		  window['Liferay'].Util.openToast({
            title: 'Success',
            message: 'Your request completed successfully.',
            type: 'success',
          });
		  }else if(response.status=="400"){
			  if (data.detail){
				const myErrorJSON=JSON.parse(data.detail);
				const myError=myErrorJSON[0].errorMessage;
				  window['Liferay'].Util.openToast({
					title: 'Warning',
					message: myError,
					type: 'warning',
				  });
			  }
		  }
        } else {
          window['Liferay'].Util.openToast({
            title: 'Success',
            message: 'Your request completed successfully.',
            type: 'success',
          });
          return data;
        }
      } catch (error) {
        console.error(error);
        window['Liferay'].Util.openToast({
          message: 'An error occured.',
          type: 'danger',
        });
      }
    } else {
      console.error("Liferay (JS Object) doesn't exist.");
    }
  },
  patch: async (url, payload) => {
    if (typeof window['Liferay'] != 'undefined') {
      try {
        const response = await window['Liferay'].Util.fetch(url, {
          body: JSON.stringify(payload),
          method: `PATCH`,
          headers: [['content-type', 'application/json']],
        });
        const data = await response.json();
        if (response.status) {
        	if (response.status=="200"){
      		  window['Liferay'].Util.openToast({
                  title: 'Success',
                  message: 'Your request completed successfully.',
                  type: 'success',
            });
        } else {
            window['Liferay'].Util.openToast({
              message: 'An error occured.',
              type: 'danger',
            });
            return data;
        }
        }
      } catch (error) {
        console.error(error);
        window['Liferay'].Util.openToast({
          message: 'An error occured.',
          type: 'danger',
        });
      }
    } else {
      console.error("Liferay (JS Object) doesn't exist.");
    }
  },
  put: async (url, payload) => {
    if (typeof window['Liferay'] != 'undefined') {
      try {
        const response = await window['Liferay'].Util.fetch(url, {
          body: JSON.stringify(payload),
          method: `PUT`,
          headers: [['content-type', 'application/json']],
        });
        if (response.status=="204"){
		  window['Liferay'].Util.openToast({
			title: 'Success',
			message: 'Your request completed successfully.',
			type: 'success',
		  });			
		}else{
			const data = await response.json();
			if (data.status) {
			  window['Liferay'].Util.openToast({
				title: data.status,
				message: 'An error occured.',
				type: 'danger',
			  });
			} else {
			  window['Liferay'].Util.openToast({
				title: 'Success',
				message: 'Your request completed successfully.',
				type: 'success',
			  });
			  return data;
			}
		}
      } catch (error) {
        console.error(error);
        window['Liferay'].Util.openToast({
          message: 'An error occured.',
          type: 'danger',
        });
      }
    } else {
      console.error("Liferay (JS Object) doesn't exist.");
    }
  },
  delete: async (url) => {
    if (typeof window['Liferay'] != 'undefined') {
      try {
        const response = await window['Liferay'].Util.fetch(url, {
          method: `DELETE`,
        });
        const data = await response.json();
        if (data.status) {
          window['Liferay'].Util.openToast({
            title: data.status,
            message: 'An error occured.',
            type: 'danger',
          });
        } else {
          window['Liferay'].Util.openToast({
            title: 'Success',
            message: 'Your request completed successfully.',
            type: 'success',
          });
          return data;
        }
      } catch (error) {
        console.error(error);
        window['Liferay'].Util.openToast({
          message: 'An error occured.',
          type: 'danger',
        });
      }
    } else {
      console.error("Liferay (JS Object) doesn't exist.");
    }
  },
};
window.LiferayService = LiferayService;