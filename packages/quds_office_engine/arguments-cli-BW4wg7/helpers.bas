Sub Main()
  Put text:="first"
  Put index:=99, text:="second"
End Sub
Sub Put(Optional ByVal index As Long = 1, Optional ByVal text As String = "default")
  Worksheets(index).Range("A1").Value2 = text
End Sub
