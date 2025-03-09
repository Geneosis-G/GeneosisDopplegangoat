class DopplegangoatInteraction extends Interaction;

var Dopplegangoat myMut;

function InitDopplegangoatInteraction(Dopplegangoat newMut)
{
	myMut=newMut;
}

exec function SelectModel(string modelname)
{
	myMut.SelectModel(modelname);
}

exec function ListModelsFrom(int index)
{
	myMut.ListModelsFrom(index);
}