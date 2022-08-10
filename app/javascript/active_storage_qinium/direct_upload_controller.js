import { Controller } from "stimulus";
import { DirectUpload } from "./direct_upload_controller/direct_upload";

export default class extends Controller {
  static targets = ['file'];
  static values = {
    'url': String
  }

  initialize(){
    this.onFileChange = this.onFileChange.bind(this)
  }

  connect(){
    this.hiddenInput = document.createElement("input")
    this.hiddenInput.type = "hidden"
    this.hiddenInput.name = this.fileTarget.name
    this.fileTarget.removeAttribute('name')
    this.fileTarget.insertAdjacentElement("beforebegin", this.hiddenInput)
    this.fileTarget.addEventListener('change', this.onFileChange)
  }

  disconnect(){
    this.fileTarget.removeEventListener('change', this.onFileChange)
  }

  onFileChange(event){
    const { target } = event
    const { files } = target
    const directUpload = new DirectUpload(files[0], this.urlValue, this)

    directUpload.create((error, attributes) => {
      if(error){
        this.hiddenInput.removeAttribute('value')
      }else{
        this.hiddenInput.setAttribute('value', attributes.signed_id)
      }
    })
  }

  // DirectUpload delegate

  directUploadWillCreateBlobWithXHR(xhr) {
    // this.dispatch("before-blob-request", { xhr })
  }

  directUploadWillStoreFileWithXHR(xhr) {
    // this.dispatch("before-storage-request", { xhr })
    xhr.upload.addEventListener("progress", event => this.uploadRequestDidProgress(event))
  }

  uploadRequestDidProgress(event){

  }
}
