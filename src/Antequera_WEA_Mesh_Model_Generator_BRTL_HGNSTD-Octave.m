clear all;
close all;

% pkg install -forge image;
pkg load image;
pkg load io;
pkg load windows;

%POINT IN POLYGON CHECK

%select image file
[filename,path]=uigetfile({'*.png';'*.jpg'},'file selector');
Image = strcat(path,filename);
[O, map, alpha] = imread(Image); #since image is B&W, output is already in bool
B = im2bw(O,0.5);
[row_px, col_px, z_px] = size(B); 

%%enter structure dimensions

prompt = {'Enter the actual horizontal structure size in mm:','Enter the actual vertical structure size in mm:'};
dlgtitle = 'Structure Dimensions';
dims = [1 1]; %% height of each text field
answer = inputdlg(prompt,dlgtitle,dims);
col_mm = str2double(answer{1});
row_mm = str2double(answer{2});


%%ratio of mm/px
ratio = max(row_mm/row_px , col_mm/col_px);

%%Image to grayscale - removed; not needed

%%Image to binary (threshold can be adjusted) - removed; not needed

%Coordinate Matching

prompt = {'Enter x coordinate (mm) of the upper left corner of the structure:','Enter y coordinate (mm) of the upper left corner of the structure:'};
dlgtitle = 'Coordinate Matching';
dims = [1 1]; %% height of each text field
answer = inputdlg(prompt,dlgtitle,dims);
x_global = str2double(answer{1});
y_global = str2double(answer{2});


%Array of Coordinates for Crack Centroids
## This overrides the nested for loops previously implemented in MATLAB, for
## performance reasons.

%% get x,y subscript locations of zero elements (i.e. black/crack)
[crack_yidx, crack_xidx] = find(~B); 

%% get centroid of zero elements/pixel
xq = x_global + ((crack_xidx - 0.5) * ratio); 
yq = y_global + ((crack_yidx - 0.5) * ratio); 


%ENTER EXPORTED MESH MODEL

prompt = {'Enter file name of mesh information spreadsheet:','Enter sheet name:','Enter range for node coordinates:','Enter range for element type, nodes, and geometry:'};
dlgtitle = 'Exported Mesh Information';
dims = [1 1 1 1]; %% height of each text field
answer = inputdlg(prompt,dlgtitle,dims);
file_name = answer{1};
sheet_name = answer{2};
info_range_node = answer{3};
info_range_element = answer{4};
#{
file_name = "Antequera_Mesh_Model_BRTL_HGNSTD.xlsx";
sheet_name = "Sheet1";
info_range_node = "E11:G46635";
info_range_element = "J11:T7039";
#}

Node_Coord = xlsread(file_name, sheet_name, info_range_node, "oct");
Elem_Type_Nodes = xlsread(file_name, sheet_name, info_range_element, "oct");


[row_nodes, col_nodes] = size(Node_Coord);
[row_elem, col_elem] = size(Elem_Type_Nodes);

Elem_Cracks = zeros(row_elem,2);
    

for i = 1:row_elem
    
    %For Hexa/Quad Mesh
    if Elem_Type_Nodes(i,9) > 0 && Elem_Type_Nodes(i,10) > 0 
        xv = zeros(8,1);
        yv = zeros(8,1);
        
        %Define vertices of the Element in the current iteration
        for j = 1:8 
            for k = 1:row_nodes
                if Elem_Type_Nodes(i,j+2) == Node_Coord(k,1)
                    xv(j,1) = Node_Coord(k,2);
                    yv(j,1) = Node_Coord(k,3);

                end
            end
        end
        
        %Count of crack centroids within each element
        [in,on] = inpolygon(xq,yq,xv,yv);
        Elem_Cracks(i,1)= Elem_Type_Nodes(i,1);
        Elem_Cracks(i,2)= numel(xq(in))+ numel(xq(on));
    
    %For Tetra/Triangle Mesh
    elseif Elem_Type_Nodes(i,9) == 0 && Elem_Type_Nodes(i,10) == 0
        
        xv = zeros(6,1);
        yv = zeros(6,1);
        
        %Define vertices of the Element in the current iteration
        for j = 1:6 
            for k = 1:row_nodes
                if Elem_Type_Nodes(i,j+2)== Node_Coord(k,1)
                    xv(j,1) = Node_Coord(k,2);
                    yv(j,1) = Node_Coord(k,3);

                end
            end
        end
        
        %Count of crack centroids within each element
        [in,on] = inpolygon(xq,yq,xv,yv);
        Elem_Cracks(i,1)= Elem_Type_Nodes(i,1);
        Elem_Cracks(i,2)= numel(xq(in))+ numel(xq(on));
      
    end
    
    
end 

diary Antequera_WEA_Mesh_data_BRTL_HGNSTD.out

%TENSILE STRENGTH REDUCTION

%%Insert Material Properties

prompt = {'Tensile Strength (MPa):','Modulus of Elasticity (MPa)','Compressive Strength (MPa)','Poisson Ratio', 'Mass Density (kg/m3)', 'Element Size (mm)' };
dlgtitle = 'Concrete Material Properties';
dims = [1 1 1 1 1 1]; ## height of text field
answer = inputdlg(prompt,dlgtitle,dims);
fct = str2double(answer{1});
E_c = str2double(answer{2});
fc_c = str2double(answer{3});
pr = str2double(answer{4});
den  = str2double(answer{5});
h = str2double(answer{6});

#{
fct = 2.58;
E_c = 2955.58;
fc_c = 25.29;
pr = 0.2;
den  = 2000;
h = 120;
#}

%%computing residual/reduced material properties per mesh 
%%creating a array containing info per mesh

Elem_WEA_info = zeros(row_elem,7);

for i = 1:row_elem
        
        w_c = Elem_Cracks(i,2)*ratio/h/1000;
       
        if  w_c > 0
            status = 0; # "cracked"; overriden previous string assignment (VERIFY)
            fct_c = 0.01;
 
        else
            status = 1; # "uncracked"; overriden previous string assignment (VERIFY)
            fct_c = fct;
        end
        
        Elem_WEA_info(i,1) = Elem_Cracks(i,1);
        Elem_WEA_info(i,2) = status;
        Elem_WEA_info(i,3) = fct_c;
end

    %%Obtaining unique material sets

    Mat_sets = unique(Elem_WEA_info(:,3));
    
    [row_Mat_sets,col_Mat_sets] = size(Mat_sets);
    
    for i = 1: row_Mat_sets
          
    fprintf('   %d NAME   "%f"\n', i+2,Mat_sets(i,1));
    fprintf('     MCNAME CONCR\n');
    fprintf('     MATMDL TSCR\n');
    fprintf('     ASPECT\n');
    fprintf('     YOUNG    %.5fE+00\n',E_c);
    
    if i == row_Mat_sets
    fprintf('     POISON   %.5fE+00\n',pr);
    else
    fprintf('     POISON   0.00000E+00\n');
    end
    
    fprintf('     DENSIT   %.5fE-12\n',den);
    fprintf('     TOTCRK ROTATE\n');
    fprintf('     TENCRV BRITTL\n');
    fprintf('     TENSTR   %.5fE+00\n',Mat_sets(i,1));
    
    fprintf('     POIRED NONE\n');
    fprintf('     COMCRV HOGNES\n');
    fprintf('     COMSTR   %.5fE+00\n',fc_c);
    fprintf('     REDCRV NONE\n');
    fprintf('     CNFCRV NONE\n');
       
    end
    
%%Create Element Set

prompt = {'Enter space-separated Concrete Geomtery Set Numbers'};
dlgtitle = 'Geometry Sets for concrete';
dims = [1]; ## height of text field
answer = inputdlg(prompt,dlgtitle,dims);
Geom = str2num(answer{1});

[arb, Geom_set] = size(Geom);

for i=1:Geom_set
    for j=1:row_Mat_sets
    
    %%Check if a possible Element set contains an element
    %%Else do not generate an element set
    
    temp = 0;
        for k = 1:row_elem
                if Elem_WEA_info(k,3) == Mat_sets(j,1) && Elem_Type_Nodes(k,11) == Geom (1,i) 
                temp = 1;
                
                k = row_elem;
                end
        end
        
        %%Print Syntax for Element/Mesh sets
        
        if temp == 1
        
            fprintf('SET  "%.6f - %d"\n', Mat_sets(j,1),Geom (1,i));
            fprintf('CONNECT\n')

            for k = 1:row_elem
                if Elem_WEA_info(k,3) == Mat_sets(j,1) && Elem_Type_Nodes(k,11) == Geom (1,i)  

                    if Elem_Type_Nodes(k,9) > 0 && Elem_Type_Nodes(k,10) > 0
                    
                        fprintf('   %d CQ40S  %d %d %d %d %d %d %d %d\n', Elem_Type_Nodes(k,1), Elem_Type_Nodes(k,3), Elem_Type_Nodes(k,4), Elem_Type_Nodes(k,5), Elem_Type_Nodes(k,6),Elem_Type_Nodes(k,7),Elem_Type_Nodes(k,8),Elem_Type_Nodes(k,9),Elem_Type_Nodes(k,10) );
                    
                    end
                    
                    if Elem_Type_Nodes(k,9) == 0 && Elem_Type_Nodes(k,10) == 0    
                    
                        fprintf('   %d CT30S  %d %d %d %d %d %d \n', Elem_Type_Nodes(k,1), Elem_Type_Nodes(k,3), Elem_Type_Nodes(k,4), Elem_Type_Nodes(k,5), Elem_Type_Nodes(k,6),Elem_Type_Nodes(k,7),Elem_Type_Nodes(k,8));
                    
                    end
                    
                end          
            end
        
        
        fprintf('MATERIAL %d\n', j+2);
        fprintf('GEOMETRY %d\n',Geom (1,i))          
        end
        

    end
end
        
diary off;

