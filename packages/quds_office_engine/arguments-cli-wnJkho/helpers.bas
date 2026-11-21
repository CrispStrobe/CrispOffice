Sub Main()
  Put text:="first"
  Put text:="second"
End Sub
Sub Put(Optional ByVal index As Long = 1, Optional ByVal text As String = "default")
  ActivePresentation.Slides(index).Shapes("Title").TextFrame.TextRange.Text = text
End Sub
