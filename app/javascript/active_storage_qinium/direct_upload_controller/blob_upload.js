export class BlobUpload {
  constructor(blob) {
    this.blob = blob
    this.file = blob.file
    this.dataBuilder = blob.dataBuilder || ((ctx) => ctx.file.slice())
    const { url, headers } = blob.directUploadData
    this.xhr = new XMLHttpRequest
    this.xhr.open("POST", url, true)
    // this.xhr.responseType = "text"
    for (const key in headers) {
      this.xhr.setRequestHeader(key, headers[key])
    }
    this.xhr.addEventListener("load", event => this.requestDidLoad(event))
    this.xhr.addEventListener("error", event => this.requestDidError(event))
  }

  create(callback) {
    // debugger
    this.callback = callback
    if(this.blob.directUploadData.formData){
      var formData
      formData = new FormData()
      for(const key in this.blob.directUploadData.formData){
        formData.append(key, this.blob.directUploadData.formData[key])
      }
      formData.append('file', this.file)
      this.xhr.send(formData)
    }else{
      this.xhr.send(this.dataBuilder(this.blob))
    }
  }

  requestDidLoad(event) {
    const { status, response } = this.xhr
    if (status >= 200 && status < 300) {
      this.callback(null, response)
    } else {
      this.requestDidError(event)
    }
  }

  requestDidError(event) {
    this.callback(event, this)
  }
}
